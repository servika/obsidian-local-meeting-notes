// meeting-engine - Phase 1 capture spike
//
// Captures a meeting as TWO separate tracks, with no virtual device:
//   • system audio (the other participants) via Core Audio process taps
//     (AudioHardwareCreateProcessTap, macOS 14.4+)
//   • your microphone via AVAudioEngine
//
// Keeping them separate gives "me vs. them" speaker separation for free.
//
// Usage:  meeting-engine [seconds] [outputBasePath]
//   defaults: 8 seconds → /tmp/meeting-engine.system.wav + .mic.wav
//
// Play some audio and talk while it runs, then inspect the two WAVs.

import Foundation
import CoreAudio
import AVFoundation

// MARK: - helpers

func log(_ msg: String) { print("[meeting-engine] \(msg)") }

func fail(_ label: String, _ status: OSStatus) -> Never {
	FileHandle.standardError.write(Data("[meeting-engine] \(label) failed: OSStatus \(status)\n".utf8))
	exit(1)
}

func require(_ status: OSStatus, _ label: String) {
	if status != noErr { fail(label, status) }
}

/// Open a WAV whose processing format matches `format` exactly (avoids -50 on write).
func openWav(_ url: URL, _ format: AVAudioFormat) -> AVAudioFile? {
	try? AVAudioFile(
		forWriting: url,
		settings: format.settings,
		commonFormat: format.commonFormat,
		interleaved: format.isInterleaved)
}

func tapUID(_ tapID: AudioObjectID) -> CFString? {
	var address = AudioObjectPropertyAddress(
		mSelector: kAudioTapPropertyUID,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var size = UInt32(MemoryLayout<CFString>.size)
	var uid: Unmanaged<CFString>?
	let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uid)
	return status == noErr ? uid?.takeRetainedValue() : nil
}

func tapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
	var address = AudioObjectPropertyAddress(
		mSelector: kAudioTapPropertyFormat,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
	var asbd = AudioStreamBasicDescription()
	let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
	return status == noErr ? asbd : nil
}

// MARK: - args

let seconds = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 8) : 8
let outBase = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/meeting-engine"
let systemURL = URL(fileURLWithPath: outBase + ".system.wav")
let micURL = URL(fileURLWithPath: outBase + ".mic.wav")

// MARK: - system-audio track (Core Audio process tap)

let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDescription.name = "meeting-engine-system-tap"
tapDescription.isPrivate = true
tapDescription.muteBehavior = .unmuted // keep the user hearing the meeting

var tapID = AudioObjectID(kAudioObjectUnknown)
require(AudioHardwareCreateProcessTap(tapDescription, &tapID), "AudioHardwareCreateProcessTap")
guard let uid = tapUID(tapID) else { fail("read tap UID", -1) }
guard var sysASBD = tapFormat(tapID) else { fail("read tap format", -1) }
log(String(format: "system tap: %.0f Hz, %u ch", sysASBD.mSampleRate, sysASBD.mChannelsPerFrame))

let aggDescription: [String: Any] = [
	kAudioAggregateDeviceNameKey as String: "meeting-engine-agg",
	kAudioAggregateDeviceUIDKey as String: "com.servika.meeting-engine.agg.\(UUID().uuidString)",
	kAudioAggregateDeviceIsPrivateKey as String: true,
	kAudioAggregateDeviceIsStackedKey as String: false,
	kAudioAggregateDeviceTapAutoStartKey as String: true,
	kAudioAggregateDeviceTapListKey as String: [
		[kAudioSubTapUIDKey as String: uid, kAudioSubTapDriftCompensationKey as String: true],
	],
]
var aggID = AudioObjectID(kAudioObjectUnknown)
require(AudioHardwareCreateAggregateDevice(aggDescription as CFDictionary, &aggID),
	"AudioHardwareCreateAggregateDevice")

guard let sysFormat = AVAudioFormat(streamDescription: &sysASBD) else { fail("system AVAudioFormat", -1) }
var systemSink = openWav(systemURL, sysFormat)
if systemSink == nil { log("⚠️  could not open \(systemURL.lastPathComponent)") }

var sysWriteErrLogged = false
let captureQueue = DispatchQueue(label: "com.servika.meeting-engine.capture")
var ioProcID: AudioDeviceIOProcID?
let ioBlock: AudioDeviceIOBlock = { _, inInputData, _, _, _ in
	guard let buffer = AVAudioPCMBuffer(pcmFormat: sysFormat, bufferListNoCopy: inInputData) else { return }
	do {
		try systemSink?.write(from: buffer)
	} catch {
		if !sysWriteErrLogged { sysWriteErrLogged = true
			FileHandle.standardError.write(Data("[meeting-engine] system write error: \(error)\n".utf8)) }
	}
}
require(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, captureQueue, ioBlock),
	"AudioDeviceCreateIOProcIDWithBlock")

// MARK: - microphone track (AVAudioEngine)

let engine = AVAudioEngine()
let micInput = engine.inputNode
let micFormat = micInput.outputFormat(forBus: 0)
var micSink: AVAudioFile?
var micActive = false

if micFormat.sampleRate > 0 && micFormat.channelCount > 0 {
	log(String(format: "mic: %.0f Hz, %u ch", micFormat.sampleRate, micFormat.channelCount))
	micSink = openWav(micURL, micFormat)
	micInput.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
		try? micSink?.write(from: buffer)
	}
	do {
		try engine.start()
		micActive = true
	} catch {
		log("⚠️  mic engine failed to start (permission?): \(error.localizedDescription)")
		micSink = nil
	}
} else {
	log("⚠️  microphone unavailable (permission not granted?) - capturing system only")
}

// MARK: - run

require(AudioDeviceStart(aggID, ioProcID), "AudioDeviceStart")
log("recording \(seconds)s → \(systemURL.path) + \(micURL.lastPathComponent)")
log("▶️  play some audio AND talk now…")
Thread.sleep(forTimeInterval: seconds)

// MARK: - stop + finalize

AudioDeviceStop(aggID, ioProcID)
if let proc = ioProcID { AudioDeviceDestroyIOProcID(aggID, proc) }
AudioHardwareDestroyAggregateDevice(aggID)
AudioHardwareDestroyProcessTap(tapID)

if micActive {
	engine.stop()
	micInput.removeTap(onBus: 0)
}

let sysFrames = systemSink?.length ?? 0
let micFrames = micSink?.length ?? 0
systemSink = nil // release → flush WAV headers
micSink = nil

func report(_ label: String, _ frames: AVAudioFramePosition, _ rate: Double, _ url: URL) {
	if frames > 0 {
		log("✅ \(label): \(frames) frames (~\(String(format: "%.1f", Double(frames) / rate))s) → \(url.path)")
	} else {
		log("⚠️  \(label): no frames captured (permission denied, or nothing playing)")
	}
}
report("system", sysFrames, sysASBD.mSampleRate, systemURL)
report("mic", micFrames, micFormat.sampleRate > 0 ? micFormat.sampleRate : 1, micURL)