// meeting-engine CLI - thin wrapper over MeetingEngineCore.
//
// Usage:  meeting-engine [seconds] [outputBasePath] [appNameToTap]
//
// Note: as a CLI it cannot obtain the macOS system-audio-recording permission,
// so the system track will be silent until the engine runs inside the signed
// GUI app (MeetingEngineApp). This CLI is for headless/dev iteration of the
// capture pipeline itself.

import Foundation
import MeetingEngineCore

let seconds = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 8) : 8
let outBase = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/meeting-engine"
let appName = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil

do {
	let result = try MeetingEngine.record(seconds: seconds, outBase: outBase, appName: appName) { msg in
		print("[meeting-engine] \(msg)")
	}
	func report(_ label: String, _ frames: Int64, _ url: URL) {
		if frames > 0 {
			print("[meeting-engine] ✅ \(label): \(frames) frames -> \(url.path)")
		} else {
			print("[meeting-engine] ⚠️  \(label): no frames captured")
		}
	}
	report("system", result.systemFrames, result.systemURL)
	report("mic", result.micFrames, result.micURL)
} catch {
	FileHandle.standardError.write(Data("[meeting-engine] error: \(error)\n".utf8))
	exit(1)
}