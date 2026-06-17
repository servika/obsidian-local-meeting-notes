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
		log: @escaping (String) -> Void
	) throws -> CaptureResult {
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
			try? systemSink?.write(from: buf)
		}
		try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, captureQueue, ioBlock),
			"AudioDeviceCreateIOProcIDWithBlock")

		// 5. Mic via AVAudioEngine.
		let engine = AVAudioEngine()
		let micInput = engine.inputNode
		let micFormat = micInput.outputFormat(forBus: 0)
		var micSink: AVAudioFile?
		var micActive = false
		if micFormat.sampleRate > 0 && micFormat.channelCount > 0 {
			log(String(format: "mic: %.0f Hz, %u ch", micFormat.sampleRate, micFormat.channelCount))
			micSink = try? AVAudioFile(
				forWriting: micURL, settings: micFormat.settings,
				commonFormat: micFormat.commonFormat, interleaved: micFormat.isInterleaved)
			micInput.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buf, _ in
				try? micSink?.write(from: buf)
			}
			if (try? engine.start()) != nil { micActive = true } else { micSink = nil }
		} else {
			log("microphone unavailable (permission not granted?)")
		}

		// 6. Run.
		try check(AudioDeviceStart(aggID, ioProcID), "AudioDeviceStart")
		log("recording \(seconds)s…")
		Thread.sleep(forTimeInterval: seconds)

		// 7. Stop + finalize.
		AudioDeviceStop(aggID, ioProcID)
		if let proc = ioProcID { AudioDeviceDestroyIOProcID(aggID, proc) }
		if micActive { engine.stop(); micInput.removeTap(onBus: 0) }

		let sysFrames = systemSink?.length ?? 0
		let micFrames = micSink?.length ?? 0
		systemSink = nil
		micSink = nil

		return CaptureResult(systemFrames: sysFrames, micFrames: micFrames,
			systemURL: systemURL, micURL: micURL)
	}
}