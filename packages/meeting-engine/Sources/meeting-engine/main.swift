// meeting-engine - Phase 1 capture spike
//
// Goal: prove we can capture macOS *system audio* (the other meeting
// participants) with no virtual device (no BlackHole), using Core Audio process
// taps (macOS 14.4+). It taps the global system output, runs for N seconds, and
// writes a WAV. This is the make-or-break assumption for the hybrid architecture.
//
// Usage:  meeting-engine [seconds] [output.wav]
//   defaults: 8 seconds → /tmp/meeting-engine-capture.wav
//
// Play some audio (a video, a song) while it runs, then inspect the WAV.

import Foundation
import CoreAudio
import AVFoundation

// MARK: - small helpers

func log(_ msg: String) {
	print("[meeting-engine] \(msg)")
}

func fail(_ label: String, _ status: OSStatus) -> Never {
	FileHandle.standardError.write(
		Data("[meeting-engine] \(label) failed: OSStatus \(status)\n".utf8))
	exit(1)
}

func require(_ status: OSStatus, _ label: String) {
	if status != noErr { fail(label, status) }
}

/// Read the tap's UID (needed to reference it from an aggregate device).
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

/// Read the tap's stream format so we can match the output file to it.
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
let outPath = CommandLine.arguments.count > 2
	? CommandLine.arguments[2]
	: "/tmp/meeting-engine-capture.wav"
let outURL = URL(fileURLWithPath: outPath)

// MARK: - 1. create a global system-audio tap (exclude nothing = whole system)

let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDescription.name = "meeting-engine-system-tap"
tapDescription.isPrivate = true
tapDescription.muteBehavior = .unmuted // keep the user hearing the meeting

var tapID = AudioObjectID(kAudioObjectUnknown)
require(AudioHardwareCreateProcessTap(tapDescription, &tapID), "AudioHardwareCreateProcessTap")
log("created system-audio tap (id \(tapID))")

guard let uid = tapUID(tapID) else { fail("read tap UID", -1) }
guard var asbd = tapFormat(tapID) else { fail("read tap format", -1) }
log(String(format: "tap format: %.0f Hz, %u ch", asbd.mSampleRate, asbd.mChannelsPerFrame))

// MARK: - 2. wrap the tap in a private aggregate device so we can run an IO proc

let aggUID = "com.servika.meeting-engine.agg.\(UUID().uuidString)"
let aggDescription: [String: Any] = [
	kAudioAggregateDeviceNameKey as String: "meeting-engine-agg",
	kAudioAggregateDeviceUIDKey as String: aggUID,
	kAudioAggregateDeviceIsPrivateKey as String: true,
	kAudioAggregateDeviceIsStackedKey as String: false,
	kAudioAggregateDeviceTapAutoStartKey as String: true,
	kAudioAggregateDeviceTapListKey as String: [
		[
			kAudioSubTapUIDKey as String: uid,
			kAudioSubTapDriftCompensationKey as String: true,
		],
	],
]

var aggID = AudioObjectID(kAudioObjectUnknown)
require(AudioHardwareCreateAggregateDevice(aggDescription as CFDictionary, &aggID),
	"AudioHardwareCreateAggregateDevice")
log("created aggregate device (id \(aggID))")

// MARK: - 3. open the output file in the tap's format

guard let format = AVAudioFormat(streamDescription: &asbd) else { fail("build AVAudioFormat", -1) }
log("buffer format: interleaved=\(format.isInterleaved) common=\(format.commonFormat.rawValue)")
var sink: AVAudioFile?
do {
	// Match the file's processing format to the tap buffer exactly, otherwise
	// ExtAudioFileWrite rejects the buffer with -50 (paramErr).
	sink = try AVAudioFile(
		forWriting: outURL,
		settings: format.settings,
		commonFormat: format.commonFormat,
		interleaved: format.isInterleaved)
} catch {
	FileHandle.standardError.write(Data("[meeting-engine] open output failed: \(error)\n".utf8))
	exit(1)
}

// MARK: - 4. install an IO proc that writes captured frames to the file

var writeErrorLogged = false
let captureQueue = DispatchQueue(label: "com.servika.meeting-engine.capture")

var ioProcID: AudioDeviceIOProcID?
let ioBlock: AudioDeviceIOBlock = { _, inInputData, _, _, _ in
	guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData)
	else { return }
	do {
		try sink?.write(from: buffer)
	} catch {
		if !writeErrorLogged {
			writeErrorLogged = true
			FileHandle.standardError.write(Data("[meeting-engine] write error: \(error)\n".utf8))
		}
	}
}

require(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggID, captureQueue, ioBlock),
	"AudioDeviceCreateIOProcIDWithBlock")
require(AudioDeviceStart(aggID, ioProcID), "AudioDeviceStart")

log("recording \(seconds)s → \(outURL.path)")
log("▶️  play some audio now (a video, a song)…")
Thread.sleep(forTimeInterval: seconds)

// MARK: - 5. stop and tear everything down

AudioDeviceStop(aggID, ioProcID)
if let proc = ioProcID { AudioDeviceDestroyIOProcID(aggID, proc) }
AudioHardwareDestroyAggregateDevice(aggID)
AudioHardwareDestroyProcessTap(tapID)

let writtenFrames = sink?.length ?? 0
sink = nil // release the last reference → finalizes/flushes the WAV header

if writtenFrames > 0 {
	let secs = Double(writtenFrames) / asbd.mSampleRate
	log("✅ done - wrote \(writtenFrames) frames (~\(String(format: "%.1f", secs))s) to \(outURL.path)")
} else {
	log("⚠️  done, but no audio frames were captured.")
	log("    Likely causes: permission not granted, or nothing was playing.")
}