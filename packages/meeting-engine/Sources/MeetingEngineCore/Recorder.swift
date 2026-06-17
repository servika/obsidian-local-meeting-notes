// MeetingEngineCore - the validated capture engine, reusable from the CLI and
// the GUI app. Captures macOS system audio (no virtual device) via Core Audio
// process taps plus the microphone, as two separate tracks.
//
// NOTE: system-audio capture requires the host to hold the macOS
// "Screen & System Audio Recording" permission. That permission can only be
// obtained by a real, signed app (not a CLI) - which is why this core is wrapped
// in a GUI app target.

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

public struct CaptureResult {
	public let systemFrames: Int64
	public let micFrames: Int64
	public let systemURL: URL
	public let micURL: URL
}

public enum MeetingEngine {

	/// Capture system audio + mic for `seconds` to `<outBase>.system.wav` and
	/// `<outBase>.mic.wav`. If `appName` is set, taps that app specifically;
	/// otherwise taps all system audio. `log` receives human-readable progress.
	public static func record(
		seconds: Double,
		outBase: String,
		appName: String?,
		onLevel: ((Float, Float) -> Void)? = nil,
		log: @escaping (String) -> Void
	) throws -> CaptureResult {
		// Latest peak levels (0…1) for the live meters, written from the audio
		// threads and sampled by a timer below.
		var systemLevel: Float = 0
		var micLevel: Float = 0
		let systemURL = URL(fileURLWithPath: (outBase as NSString).expandingTildeInPath + ".system.wav")
		let micURL = URL(fileURLWithPath: (outBase as NSString).expandingTildeInPath + ".mic.wav")

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

		var tapID = AudioObjectID(kAudioObjectUnknown)
		try check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "AudioHardwareCreateProcessTap")
		defer { AudioHardwareDestroyProcessTap(tapID) }

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
		var aggID = AudioObjectID(kAudioObjectUnknown)
		try check(AudioHardwareCreateAggregateDevice(aggDescription as CFDictionary, &aggID),
			"AudioHardwareCreateAggregateDevice")
		defer { AudioHardwareDestroyAggregateDevice(aggID) }

		// 3. Output files.
		guard let sysFormat = AVAudioFormat(streamDescription: &sysASBD) else {
			throw EngineError(message: "could not build system AVAudioFormat")
		}
		var systemSink: AVAudioFile? = try AVAudioFile(
			forWriting: systemURL, settings: sysFormat.settings,
			commonFormat: sysFormat.commonFormat, interleaved: sysFormat.isInterleaved)

		// 4. System IO proc.
		let captureQueue = DispatchQueue(label: "com.servika.meeting-engine.capture")
		var ioProcID: AudioDeviceIOProcID?
		let ioBlock: AudioDeviceIOBlock = { _, inInputData, _, _, _ in
			guard let buf = AVAudioPCMBuffer(pcmFormat: sysFormat, bufferListNoCopy: inInputData) else { return }
			systemLevel = bufferPeak(buf)
			try? systemSink?.write(from: buf)
		}
		try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, captureQueue, ioBlock),
			"AudioDeviceCreateIOProcIDWithBlock")

		// 5a. Microphone permission. AVAudioEngine input silently delivers no frames
		// when mic access isn't granted, and never prompts on its own - so request
		// it explicitly here (this is the call that surfaces the TCC prompt).
		if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
			let sem = DispatchSemaphore(value: 0)
			AVCaptureDevice.requestAccess(for: .audio) { _ in sem.signal() }
			sem.wait()
		}
		if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
			log("microphone access not granted - mic track will be empty (grant it in System Settings → Privacy & Security → Microphone)")
		}

		// 5. Mic via AVCaptureSession. Records the input device independently of the
		// output device - unlike AVAudioEngine, which couples input+output and
		// delivers no frames when the output is a Bluetooth device. Records to a
		// temp CAF, converted to the expected .mic.wav on stop.
		let micSession = AVCaptureSession()
		let micFileOutput = AVCaptureAudioFileOutput()
		let micDelegate = MicRecordingDelegate()
		let micTempCAF = URL(fileURLWithPath: NSTemporaryDirectory() + "me-mic-\(UUID().uuidString).caf")
		var micActive = false
		if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
			let micDevice = AVCaptureDevice.default(for: .audio) {
			do {
				let input = try AVCaptureDeviceInput(device: micDevice)
				if micSession.canAddInput(input) { micSession.addInput(input) }
				if micSession.canAddOutput(micFileOutput) { micSession.addOutput(micFileOutput) }
				micSession.startRunning()
				micFileOutput.startRecording(to: micTempCAF, outputFileType: .caf, recordingDelegate: micDelegate)
				micActive = true
				log("mic: \(micDevice.localizedName)")
			} catch {
				log("mic capture failed to start: \(error.localizedDescription)")
			}
		} else {
			log("microphone unavailable or not authorized - mic track will be empty")
		}

		// 6. Run. Sample the levels ~20×/sec for the live meters, decoupled from
		// the audio callback rate.
		var levelTimer: DispatchSourceTimer?
		if let onLevel = onLevel {
			let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.servika.meeting-engine.levels"))
			t.schedule(deadline: .now(), repeating: 0.05)
			t.setEventHandler {
				if micActive, let ch = micFileOutput.connection(with: .audio)?.audioChannels.first {
					let db = ch.averagePowerLevel
					micLevel = db <= -80 ? 0 : Float(pow(10.0, Double(db) / 20.0))
				}
				onLevel(systemLevel, micLevel)
			}
			t.resume()
			levelTimer = t
		}

		try check(AudioDeviceStart(aggID, ioProcID), "AudioDeviceStart")
		log("recording \(seconds)s…")
		Thread.sleep(forTimeInterval: seconds)

		// 7. Stop + finalize.
		levelTimer?.cancel()
		onLevel?(0, 0)
		AudioDeviceStop(aggID, ioProcID)
		if let proc = ioProcID { AudioDeviceDestroyIOProcID(aggID, proc) }

		var micFrames: Int64 = 0
		if micActive {
			micFileOutput.stopRecording()
			_ = micDelegate.done.wait(timeout: .now() + 5) // wait for the file to finalize
			micSession.stopRunning()
			try? FileManager.default.removeItem(at: micURL)
			do {
				try runProcess("/usr/bin/afconvert",
					["-f", "WAVE", "-d", "LEI16", "-c", "1", micTempCAF.path, micURL.path])
				if let f = try? AVAudioFile(forReading: micURL) { micFrames = f.length }
			} catch {
				log("mic conversion failed: \(error.localizedDescription)")
			}
			try? FileManager.default.removeItem(at: micTempCAF)
		}

		let sysFrames = systemSink?.length ?? 0
		systemSink = nil

		return CaptureResult(systemFrames: sysFrames, micFrames: micFrames,
			systemURL: systemURL, micURL: micURL)
	}
}