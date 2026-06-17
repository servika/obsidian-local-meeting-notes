// Transcription + "You vs. Them" diarization.
//
// Each captured track is transcribed separately with whisper.cpp, then the two
// segment lists are merged by timestamp into one speaker-labeled transcript.
// Because mic and system audio are already separate tracks, "who spoke" comes
// for free - no diarization model needed.

import Foundation

public struct TranscriptSegment {
	public let start: Double // seconds
	public let end: Double
	public let text: String
	public let speaker: String
}

public enum Transcriber {

	/// Transcribe one WAV (any format) and tag every segment with `speaker`.
	/// Converts to whisper's required 16 kHz mono 16-bit via `afconvert`, then
	/// runs `whisper-cli -oj` and parses the JSON segments.
	public static func transcribe(
		wavPath: String,
		model: String,
		whisperBin: String = "whisper-cli",
		language: String = "auto",
		speaker: String,
		progress: ((Double) -> Void)? = nil,
		log: (String) -> Void
	) throws -> [TranscriptSegment] {
		let modelPath = (model as NSString).expandingTildeInPath
		guard FileManager.default.fileExists(atPath: modelPath) else {
			throw EngineError(message: "whisper model not found: \(modelPath)")
		}
		let src = (wavPath as NSString).expandingTildeInPath
		guard FileManager.default.fileExists(atPath: src) else {
			log("\(speaker): audio track not found, skipping")
			return []
		}

		let base = NSTemporaryDirectory() + "me-tx-\(UUID().uuidString)"
		let wav16 = base + ".16k.wav"
		defer { try? FileManager.default.removeItem(atPath: wav16) }

		log("converting \((src as NSString).lastPathComponent) -> 16 kHz mono")
		try runProcess("/usr/bin/afconvert",
			["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", src, wav16])

		log("transcribing \(speaker) track…")
		try runWhisper(resolveBinary(whisperBin),
			["-m", modelPath, "-f", wav16, "-l", language, "-oj", "-pp", "-of", base],
			progress: progress)

		let jsonPath = base + ".json"
		defer { try? FileManager.default.removeItem(atPath: jsonPath) }
		// A silent/empty track produces no JSON - treat that as zero segments
		// rather than failing the whole transcription.
		guard FileManager.default.fileExists(atPath: jsonPath) else {
			log("\(speaker): no speech detected")
			return []
		}
		let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
		guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			let rawSegs = root["transcription"] as? [[String: Any]]
		else { throw EngineError(message: "could not parse whisper JSON output") }

		var segments: [TranscriptSegment] = []
		for seg in rawSegs {
			let text = (seg["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			if text.isEmpty { continue }
			let offsets = seg["offsets"] as? [String: Any]
			let from = numberMS(offsets?["from"])
			let to = numberMS(offsets?["to"])
			segments.append(TranscriptSegment(start: from / 1000, end: to / 1000, text: text, speaker: speaker))
		}
		return segments
	}

	/// Merge segments from all speakers into a chronological, labeled transcript.
	/// Consecutive segments from the same speaker are collapsed into one line.
	public static func diarizedMarkdown(_ segments: [TranscriptSegment]) -> String {
		let sorted = segments.sorted { $0.start < $1.start }
		var lines: [String] = []
		var speaker = ""
		var buffer = ""
		func flush() {
			let t = buffer.trimmingCharacters(in: .whitespaces)
			if !t.isEmpty { lines.append("**\(speaker):** \(t)") }
			buffer = ""
		}
		for seg in sorted {
			if seg.speaker != speaker { flush(); speaker = seg.speaker }
			buffer += (buffer.isEmpty ? "" : " ") + seg.text
		}
		flush()
		return lines.joined(separator: "\n\n")
	}

	/// Resolve a bare command to an absolute path. The app, launched via
	/// LaunchServices, has a minimal PATH that omits Homebrew, so `whisper-cli`
	/// wouldn't be found via `env`.
	private static func resolveBinary(_ name: String) -> String {
		if name.hasPrefix("/") { return name }
		for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
			let candidate = "\(dir)/\(name)"
			if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
		}
		return name // fall back to PATH via /usr/bin/env
	}

	private static func numberMS(_ value: Any?) -> Double {
		if let d = value as? Double { return d }
		if let i = value as? Int { return Double(i) }
		if let s = value as? String, let d = Double(s) { return d }
		return 0
	}
}

/// Run a process to completion, throwing with stderr on failure. A bare command
/// (no leading "/") is resolved via PATH using /usr/bin/env.
func runProcess(_ command: String, _ args: [String]) throws {
	let proc = Process()
	if command.hasPrefix("/") {
		proc.executableURL = URL(fileURLWithPath: command)
		proc.arguments = args
	} else {
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		proc.arguments = [command] + args
	}
	let errPipe = Pipe()
	proc.standardError = errPipe
	proc.standardOutput = Pipe()
	do {
		try proc.run()
	} catch {
		throw EngineError(message: "failed to launch \(command): \(error.localizedDescription)")
	}
	proc.waitUntilExit()
	if proc.terminationStatus != 0 {
		let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
		let errStr = String(data: errData, encoding: .utf8) ?? ""
		throw EngineError(message: "\(command) exited \(proc.terminationStatus): \(String(errStr.suffix(400)))")
	}
}

/// Run whisper-cli, streaming its stderr to report progress (0…1) parsed from
/// its `progress = NN%` lines. stdout is discarded so it can't fill the pipe.
func runWhisper(_ command: String, _ args: [String], progress: ((Double) -> Void)?) throws {
	let proc = Process()
	if command.hasPrefix("/") {
		proc.executableURL = URL(fileURLWithPath: command)
		proc.arguments = args
	} else {
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		proc.arguments = [command] + args
	}
	proc.standardOutput = FileHandle.nullDevice
	let errPipe = Pipe()
	proc.standardError = errPipe
	let handle = errPipe.fileHandleForReading
	let lock = NSLock()
	var errBuffer = Data()
	handle.readabilityHandler = { h in
		let chunk = h.availableData
		if chunk.isEmpty { return }
		lock.lock(); errBuffer.append(chunk); lock.unlock()
		if let s = String(data: chunk, encoding: .utf8), let p = lastProgressFraction(in: s) {
			progress?(p)
		}
	}
	do {
		try proc.run()
	} catch {
		handle.readabilityHandler = nil
		throw EngineError(message: "failed to launch \(command): \(error.localizedDescription)")
	}
	proc.waitUntilExit()
	handle.readabilityHandler = nil
	if proc.terminationStatus != 0 {
		lock.lock(); let s = String(data: errBuffer, encoding: .utf8) ?? ""; lock.unlock()
		throw EngineError(message: "\(command) exited \(proc.terminationStatus): \(String(s.suffix(400)))")
	}
}

/// Parse the last "progress = NN%" value from a chunk of whisper output.
private func lastProgressFraction(in s: String) -> Double? {
	var result: Double?
	for tail in s.components(separatedBy: "progress = ").dropFirst() {
		let digits = tail.prefix { $0.isNumber }
		if let n = Double(digits) { result = n / 100.0 }
	}
	return result
}