import Foundation
import CoreAudio
import AppKit

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

func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
	var addr = AudioObjectPropertyAddress(
		mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var pidVar = pid
	var obj = AudioObjectID(kAudioObjectUnknown)
	var size = UInt32(MemoryLayout<AudioObjectID>.size)
	let status = AudioObjectGetPropertyData(
		AudioObjectID(kAudioObjectSystemObject), &addr,
		UInt32(MemoryLayout<pid_t>.size), &pidVar, &size, &obj)
	return status == noErr && obj != kAudioObjectUnknown ? obj : nil
}

func findApp(_ needle: String) -> (pid: pid_t, name: String)? {
	let lower = needle.lowercased()
	for app in NSWorkspace.shared.runningApplications {
		let name = app.localizedName ?? ""
		let bid = app.bundleIdentifier ?? ""
		if name.lowercased().contains(lower) || bid.lowercased().contains(lower) {
			return (app.processIdentifier, name)
		}
	}
	return nil
}

func allAudioDevices() -> [AudioObjectID] {
	var addr = AudioObjectPropertyAddress(
		mSelector: kAudioHardwarePropertyDevices,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var size: UInt32 = 0
	guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
	else { return [] }
	let count = Int(size) / MemoryLayout<AudioObjectID>.size
	var ids = [AudioObjectID](repeating: 0, count: count)
	guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
	else { return [] }
	return ids
}

func deviceUID(_ dev: AudioObjectID) -> CFString? {
	var addr = AudioObjectPropertyAddress(
		mSelector: kAudioDevicePropertyDeviceUID,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var uid: Unmanaged<CFString>?
	var size = UInt32(MemoryLayout<CFString>.size)
	guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid) == noErr else { return nil }
	return uid?.takeRetainedValue()
}

func deviceTransport(_ dev: AudioObjectID) -> UInt32 {
	var addr = AudioObjectPropertyAddress(
		mSelector: kAudioDevicePropertyTransportType,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var t: UInt32 = 0
	var size = UInt32(MemoryLayout<UInt32>.size)
	_ = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &t)
	return t
}

func deviceHasOutput(_ dev: AudioObjectID) -> Bool {
	var addr = AudioObjectPropertyAddress(
		mSelector: kAudioDevicePropertyStreams,
		mScope: kAudioObjectPropertyScopeOutput,
		mElement: kAudioObjectPropertyElementMain)
	var size: UInt32 = 0
	guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr else { return false }
	return size > 0
}

func defaultOutputDeviceUID() -> CFString? {
	var addr = AudioObjectPropertyAddress(
		mSelector: kAudioHardwarePropertyDefaultOutputDevice,
		mScope: kAudioObjectPropertyScopeGlobal,
		mElement: kAudioObjectPropertyElementMain)
	var devID = AudioObjectID(kAudioObjectUnknown)
	var size = UInt32(MemoryLayout<AudioObjectID>.size)
	guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID) == noErr,
		devID != kAudioObjectUnknown else { return nil }
	return deviceUID(devID)
}

/// Prefer a built-in output device to clock the aggregate, so a Bluetooth output
/// is never pulled into it (which degrades it and breaks capture).
func pickClockDevice() -> (uid: CFString, kind: String)? {
	for dev in allAudioDevices() where deviceHasOutput(dev) && deviceTransport(dev) == kAudioDeviceTransportTypeBuiltIn {
		if let uid = deviceUID(dev) { return (uid, "built-in") }
	}
	if let uid = defaultOutputDeviceUID() { return (uid, "default-output") }
	return nil
}