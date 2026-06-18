// MeetingEngineCore - the validated capture engine.
//
// Captures macOS system audio (no virtual device) via Core Audio process taps
// plus the microphone (via AVCaptureSession), as two separate tracks. Use
// `MeetingRecorder` for start/stop control; `MeetingEngine.record` is a
// fixed-duration convenience for the CLI.

import Foundation
import CoreAudio
import AVFoundation
import AppKit

public struct EngineError: Error, CustomStringConvertible {
	public let message: String
	public var description: String { message }
}

private func check(_ status: OSStatus, _ label: String) throws {
	if status != noErr { throw EngineError(message: "\(label): OSStatus \(status)") }
}

public struct CaptureResult {
	public let systemFrames: Int64
	public let micFrames: Int64
	public let systemURL: URL
	public let micURL: URL
}

/// Stateful recorder: `start()` begins capture, `stop()` finalizes and returns
/// the two track files. Set `onLevel` to receive live (system, mic) peak levels.
public final class MeetingRecorder {
	private let log: (String) -> Void
	public var onLevel: ((Float, Float) -> Void)?
	public private(set) var isRecording = false

	// Capture state (valid between start and stop)
	private var tapID = AudioObjectID(kAudioObjectUnknown)
	private var aggID = AudioObjectID(kAudioObjectUnknown)
	private var ioProcID: AudioDeviceIOProcID?
	private var systemSink: AVAudioFile?
	private var sysFormat: AVAudioFormat?
	private var systemURL = URL(fileURLWithPath: "/tmp/meeting-engine.system.wav")
	private var micURL = URL(fileURLWithPath: "/tmp/meeting-engine.mic.wav")
	private let micSession = AVCaptureSession()
	private let micFileOutput = AVCaptureAudioFileOutput()
	private let micDelegate = MicRecordingDelegate()
	private var micTempCAF: URL?
	private var micActive = false
	private var levelTimer: DispatchSourceTimer?
	private var systemLevel: Float = 0
	private var micLevel: Float = 0
	private let captureQueue = DispatchQueue(label: "com.servika.meeting-engine.capture")

	public init(log: @escaping (String) -> Void) { self.log = log }

	/// Begin capturing to `<outBase>.system.wav` and `<outBase>.mic.wav`.
	public func start(outBase: String, appName: String?) throws {
		guard !isRecording else { return }
		systemURL = URL(fileURLWithPath: (outBase as NSString).expandingTildeInPath + ".system.wav")
		micURL = URL(fileURLWithPath: (outBase as NSString).expandingTildeInPath + ".mic.wav")

		// 1. Tap (per-process if an app was named, else global).
		let tapDescription: CATapDescription
		if let needle = appName, !needle.isEmpty {
			guard let (pid, name) = findApp(needle) else {
				throw EngineError(message: "no running app matching '\(needle)'")
			}
			guard let obj = processObjectID(forPID: pid) else {
				throw EngineError(message: "could not translate pid \(pid) to an audio object")
			}
			log("per-process tap on \(name) (pid \(pid))")
			tapDescription = CATapDescription(stereoMixdownOfProcesses: [obj])
		} else {
			log("global tap (all processes)")
			tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
		}
		tapDescription.name = "meeting-engine-tap"
		tapDescription.isPrivate = true
		tapDescription.muteBehavior = .unmuted

		tapID = AudioObjectID(kAudioObjectUnknown)
		try check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "AudioHardwareCreateProcessTap")
		guard let uid = tapUID(tapID) else { throw EngineError(message: "could not read tap UID") }
		guard var sysASBD = tapFormat(tapID) else { throw EngineError(message: "could not read tap format") }
		log(String(format: "system tap: %.0f Hz, %u ch", sysASBD.mSampleRate, sysASBD.mChannelsPerFrame))

		// 2. Aggregate device clocked by a built-in output (never the BT device).
		guard let (clockUID, clockKind) = pickClockDevice() else {
			throw EngineError(message: "no output device available to clock the aggregate")
		}
		log("aggregate clock: \(clockUID) (\(clockKind))")
		let aggDescription: [String: Any] = [
			kAudioAggregateDeviceNameKey as String: "meeting-engine-agg",
			kAudioAggregateDeviceUIDKey as String: "com.servika.meeting-engine.agg.\(UUID().uuidString)",
			kAudioAggregateDeviceMainSubDeviceKey as String: clockUID,
			kAudioAggregateDeviceIsPrivateKey as String: true,
			kAudioAggregateDeviceIsStackedKey as String: false,
			kAudioAggregateDeviceTapAutoStartKey as String: true,
			kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: clockUID]],
			kAudioAggregateDeviceTapListKey as String: [
				[kAudioSubTapUIDKey as String: uid, kAudioSubTapDriftCompensationKey as String: true],
			],
		]
		aggID = AudioObjectID(kAudioObjectUnknown)
		try check(AudioHardwareCreateAggregateDevice(aggDescription as CFDictionary, &aggID),
			"AudioHardwareCreateAggregateDevice")

		// 3. System output file.
		guard let fmt = AVAudioFormat(streamDescription: &sysASBD) else {
			throw EngineError(message: "could not build system AVAudioFormat")
		}
		sysFormat = fmt
		systemSink = try AVAudioFile(forWriting: systemURL, settings: fmt.settings,
			commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)

		// 4. System IO proc.
		ioProcID = nil
		let ioBlock: AudioDeviceIOBlock = { [weak self] _, inInputData, _, _, _ in
			guard let self = self, let fmt = self.sysFormat,
				let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData) else { return }
			self.systemLevel = dbNormFromLinear(bufferPeak(buf))
			try? self.systemSink?.write(from: buf)
		}
		try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, captureQueue, ioBlock),
			"AudioDeviceCreateIOProcIDWithBlock")

		// 5. Microphone permission, then capture via AVCaptureSession (independent
		// of the output device - AVAudioEngine stalls on Bluetooth output).
		if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
			let sem = DispatchSemaphore(value: 0)
			AVCaptureDevice.requestAccess(for: .audio) { _ in sem.signal() }
			sem.wait()
		}
		micActive = false
		let caf = URL(fileURLWithPath: NSTemporaryDirectory() + "me-mic-\(UUID().uuidString).caf")
		micTempCAF = caf
		if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
			let micDevice = AVCaptureDevice.default(for: .audio) {
			do {
				let input = try AVCaptureDeviceInput(device: micDevice)
				if micSession.canAddInput(input) { micSession.addInput(input) }
				if micSession.canAddOutput(micFileOutput) { micSession.addOutput(micFileOutput) }
				micSession.startRunning()
				micFileOutput.startRecording(to: caf, outputFileType: .caf, recordingDelegate: micDelegate)
				micActive = true
				log("mic: \(micDevice.localizedName)")
			} catch {
				log("mic capture failed to start: \(error.localizedDescription)")
			}
		} else {
			log("microphone unavailable or not authorized - mic track will be empty")
		}

		// 6. Live level meters.
		systemLevel = 0
		micLevel = 0
		if onLevel != nil {
			let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.servika.meeting-engine.levels"))
			t.schedule(deadline: .now(), repeating: 0.05)
			t.setEventHandler { [weak self] in
				guard let self = self else { return }
				if self.micActive, let ch = self.micFileOutput.connection(with: .audio)?.audioChannels.first {
					self.micLevel = dbNormFromDB(ch.averagePowerLevel)
				}
				self.onLevel?(self.systemLevel, self.micLevel)
			}
			t.resume()
			levelTimer = t
		}

		try check(AudioDeviceStart(aggID, ioProcID), "AudioDeviceStart")
		isRecording = true
		log("recording…")
	}

	/// Stop capturing, finalize both files, and return them.
	public func stop() -> CaptureResult {
		guard isRecording else {
			return CaptureResult(systemFrames: 0, micFrames: 0, systemURL: systemURL, micURL: micURL)
		}
		isRecording = false

		levelTimer?.cancel()
		levelTimer = nil
		onLevel?(0, 0)

		AudioDeviceStop(aggID, ioProcID)
		if let proc = ioProcID { AudioDeviceDestroyIOProcID(aggID, proc) }
		ioProcID = nil
		AudioHardwareDestroyAggregateDevice(aggID)
		AudioHardwareDestroyProcessTap(tapID)

		var micFrames: Int64 = 0
		if micActive {
			micFileOutput.stopRecording()
			_ = micDelegate.done.wait(timeout: .now() + 5) // wait for the file to finalize
			micSession.stopRunning()
			if let caf = micTempCAF {
				try? FileManager.default.removeItem(at: micURL)
				do {
					try runProcess("/usr/bin/afconvert",
						["-f", "WAVE", "-d", "LEI16", "-c", "1", caf.path, micURL.path])
					normalizeWav16(micURL.path) // boost a quiet mic
					if let f = try? AVAudioFile(forReading: micURL) { micFrames = f.length }
				} catch {
					log("mic conversion failed: \(error.localizedDescription)")
				}
				try? FileManager.default.removeItem(at: caf)
			}
		}

		let sysFrames = systemSink?.length ?? 0
		systemSink = nil

		return CaptureResult(systemFrames: sysFrames, micFrames: micFrames,
			systemURL: systemURL, micURL: micURL)
	}
}

public enum MeetingEngine {
	/// Fixed-duration convenience used by the CLI.
	public static func record(
		seconds: Double,
		outBase: String,
		appName: String?,
		onLevel: ((Float, Float) -> Void)? = nil,
		log: @escaping (String) -> Void
	) throws -> CaptureResult {
		let recorder = MeetingRecorder(log: log)
		recorder.onLevel = onLevel
		try recorder.start(outBase: outBase, appName: appName)
		Thread.sleep(forTimeInterval: seconds)
		return recorder.stop()
	}
}

/// Signals when AVCaptureAudioFileOutput has finished finalizing the mic file.
final class MicRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
	let done = DispatchSemaphore(value: 0)
	func fileOutput(
		_ output: AVCaptureFileOutput,
		didFinishRecordingTo outputFileURL: URL,
		from connections: [AVCaptureConnection],
		error: Error?
	) {
		done.signal()
	}
}

/// Map a linear peak (0…1) to a dB-based meter value (0…1), so quiet-but-present
/// speech reads as a useful level instead of a sliver. -60 dBFS → 0, 0 dBFS → 1.
func dbNormFromLinear(_ peak: Float) -> Float {
	guard peak > 1e-7 else { return 0 }
	return dbNormFromDB(20 * log10f(peak))
}

func dbNormFromDB(_ db: Float) -> Float {
	return max(0, min(1, (db + 60) / 60))
}

/// Peak-normalize a 16-bit PCM WAV in place to make a quiet mic audible. Only
/// boosts (never attenuates), skips near-silence so noise isn't amplified, and
/// caps the gain.
func normalizeWav16(_ path: String, targetPeak: Float = 0.9, maxGain: Float = 8, floor: Float = 0.003) {
	let url = URL(fileURLWithPath: path)
	guard var data = try? Data(contentsOf: url), let range = wavDataChunkRange(data) else { return }
	let count = range.count / 2
	guard count > 0 else { return }

	var samples = [Int16](repeating: 0, count: count)
	samples.withUnsafeMutableBytes { dst in
		_ = data.copyBytes(to: dst, from: range)
	}

	var peak: Int32 = 0
	for s in samples { let a = Int32(s).magnitude > 32767 ? 32767 : Int32(abs(Int32(s))); if a > peak { peak = a } }
	let peakF = Float(peak) / 32767.0
	guard peakF >= floor else { return } // basically silence
	let gain = min(targetPeak / peakF, maxGain)
	guard gain > 1.05 else { return } // already loud enough

	for i in 0..<count {
		let v = (Float(samples[i]) * gain).rounded()
		samples[i] = Int16(max(-32768, min(32767, v)))
	}
	samples.withUnsafeBytes { src in
		data.replaceSubrange(range, with: src)
	}
	try? data.write(to: url)
}

/// Byte range of the `data` chunk body in a RIFF/WAV file.
func wavDataChunkRange(_ data: Data) -> Range<Int>? {
	let bytes = [UInt8](data)
	guard bytes.count > 12, Array(bytes[0..<4]) == Array("RIFF".utf8) else { return nil }
	var pos = 12
	while pos + 8 <= bytes.count {
		let id = String(bytes: bytes[pos..<pos + 4], encoding: .ascii) ?? ""
		let size = Int(bytes[pos + 4]) | (Int(bytes[pos + 5]) << 8) | (Int(bytes[pos + 6]) << 16) | (Int(bytes[pos + 7]) << 24)
		let bodyStart = pos + 8
		if id == "data" { return bodyStart..<min(bodyStart + size, bytes.count) }
		pos = bodyStart + size + (size & 1)
	}
	return nil
}

/// Peak absolute sample amplitude (0…1) across all channels of a float buffer.
func bufferPeak(_ buffer: AVAudioPCMBuffer) -> Float {
	guard let channels = buffer.floatChannelData else { return 0 }
	let frames = Int(buffer.frameLength)
	let channelCount = Int(buffer.format.channelCount)
	var peak: Float = 0
	for c in 0..<channelCount {
		let samples = channels[c]
		for i in 0..<frames {
			let v = abs(samples[i])
			if v > peak { peak = v }
		}
	}
	return peak
}