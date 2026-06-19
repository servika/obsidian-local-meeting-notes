import Foundation
import AVFoundation
import MeetingEngineCore

/// Drives record → stop → transcribe → summarize → save-to-vault (and
/// re-generate for existing meetings), exposing observable state for the UI.
final class RecordingController: ObservableObject {
	@Published var isRecording = false
	@Published var busy = false
	@Published var status = "Ready."
	@Published var systemLevel: Float = 0
	@Published var micLevel: Float = 0
	@Published var progress: Double = 0
	@Published var elapsed: String = ""
	/// Estimated time remaining for the current processing (live, from progress).
	@Published var remaining: String = ""
	/// The meeting currently being recorded or processed (for selection + row icon).
	@Published var activeID: String?

	private var recorder: MeetingRecorder?
	private var stamp = ""
	private var procTimer: Timer?
	private var procStart: Date?
	private var cancelToken: CancelToken?
	private let settings: AppSettings
	private let store: MeetingStore

	init(settings: AppSettings, store: MeetingStore) {
		self.settings = settings
		self.store = store
	}

	func toggle() { isRecording ? stop() : start() }

	/// Stop an in-progress transcription/summarization. The recording's audio is
	/// kept, so the meeting can be re-generated later.
	func cancelProcessing() {
		cancelToken?.cancel()
		status = "Stopping…"
	}

	func start() {
		guard let meetingsDir = settings.meetingsDirURL else {
			status = "Set your Obsidian vault in Settings (⌘,)."
			return
		}
		let recordingsDir = meetingsDir.appendingPathComponent("recordings", isDirectory: true)
		try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

		stamp = Self.timestamp()
		let outBase = recordingsDir.appendingPathComponent("Meeting \(stamp)").path
		let r = MeetingRecorder(log: { [weak self] msg in DispatchQueue.main.async { self?.status = msg } })
		r.onLevel = { [weak self] s, m in DispatchQueue.main.async { self?.systemLevel = s; self?.micLevel = m } }
		do {
			try r.start(outBase: outBase, appName: nil)
			recorder = r
			isRecording = true
			status = "Recording… click Stop when the meeting ends."
			// Show the new meeting in the list immediately (and select it), so it's
			// not confused with whatever was previously highlighted.
			let title = "Meeting \(stamp)"
			let noteURL = meetingsDir.appendingPathComponent("\(title).md")
			let placeholder = Self.buildNote(title: title, date: stamp, audioBase: "recordings/Meeting \(stamp)",
				durationSeconds: 0, summary: "", transcript: "_Recording in progress…_")
			try? placeholder.write(to: noteURL, atomically: true, encoding: .utf8)
			store.reload(folder: meetingsDir)
			activeID = noteURL.path
		} catch {
			status = "Couldn't start: \(error)"
		}
	}

	func stop() {
		guard let r = recorder else { return }
		isRecording = false
		busy = true
		progress = 0
		status = "Finishing recording…"
		startElapsedTimer()
		let stamp = self.stamp
		let token = CancelToken()
		cancelToken = token
		guard let meetingsDir = settings.meetingsDirURL else { busy = false; stopElapsedTimer(); return }

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			let result = r.stop()
			DispatchQueue.main.async { self.systemLevel = 0; self.micLevel = 0 }

			let audioBase = "recordings/Meeting \(stamp)"
			// Follow a rename made during recording: find the placeholder note by
			// its audio link rather than reconstructing the original filename, so
			// we update that note instead of creating a duplicate.
			let noteURL = Self.existingNoteURL(audioBase: audioBase, in: meetingsDir)
				?? meetingsDir.appendingPathComponent("Meeting \(stamp).md")
			let title = noteURL.deletingPathExtension().lastPathComponent
			do {
				let (transcript, summary) = try self.transcribeAndSummarize(systemWav: result.systemURL.path, micWav: result.micURL.path, cancel: token)
				let note = Self.buildNote(title: title, date: stamp, audioBase: audioBase, durationSeconds: Int(result.duration.rounded()), summary: summary, transcript: transcript)
				try note.write(to: noteURL, atomically: true, encoding: .utf8)
				self.finish(status: "✅ Saved \(noteURL.lastPathComponent)")
			} catch is CancelledError {
				// Keep the recording as a re-generatable note.
				let note = Self.buildNote(title: title, date: stamp, audioBase: audioBase, durationSeconds: Int(result.duration.rounded()), summary: "",
					transcript: "_Transcription stopped. Open this meeting and click Re-generate to process it._")
				try? note.write(to: noteURL, atomically: true, encoding: .utf8)
				self.finish(status: "Stopped - re-generate when ready")
			} catch {
				self.finish(status: "Failed: \(error)")
			}
			DispatchQueue.main.async { self.recorder = nil }
		}
	}

	/// Re-transcribe + re-summarize an existing meeting from its saved audio.
	func regenerate(_ meeting: Meeting) {
		guard !busy, !isRecording else { return }
		busy = true
		progress = 0
		status = "Re-generating…"
		activeID = meeting.url.path
		startElapsedTimer()
		let token = CancelToken()
		cancelToken = token
		guard let meetingsDir = settings.meetingsDirURL else { busy = false; stopElapsedTimer(); return }
		let noteURL = meeting.url
		let title = meeting.title

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			let content = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""
			let date = Self.frontmatterValue("date", in: content) ?? title
			let audioBase = Self.frontmatterValue("audio", in: content) ?? "recordings/\(title)"
			let systemWav = meetingsDir.appendingPathComponent(audioBase + ".system.wav").path
			let micWav = meetingsDir.appendingPathComponent(audioBase + ".mic.wav").path
			let dur = Int(Self.frontmatterValue("duration", in: content) ?? "") ?? Self.audioDurationSeconds(systemWav: systemWav, micWav: micWav)

			guard FileManager.default.fileExists(atPath: systemWav) || FileManager.default.fileExists(atPath: micWav) else {
				self.finish(status: "No saved audio found for this meeting.")
				return
			}
			do {
				let (transcript, summary) = try self.transcribeAndSummarize(systemWav: systemWav, micWav: micWav, cancel: token)
				let note = Self.buildNote(title: title, date: date, audioBase: audioBase, durationSeconds: dur, summary: summary, transcript: transcript)
				try note.write(to: noteURL, atomically: true, encoding: .utf8)
				self.finish(status: "✅ Re-generated \(title)")
			} catch is CancelledError {
				self.finish(status: "Stopped. The existing note is unchanged.")
			} catch {
				self.finish(status: "Failed: \(error)")
			}
		}
	}

	// MARK: pipeline

	/// Transcribe both tracks (with weighted progress) and summarize. Runs on a
	/// background queue; updates `progress`/`status` on the main queue.
	private func transcribeAndSummarize(systemWav: String, micWav: String, cancel: CancelToken) throws -> (transcript: String, summary: String) {
		let lang = settings.language.isEmpty ? "auto" : settings.language
		let model = (settings.modelPath(for: lang) as NSString).expandingTildeInPath
		let hint = settings.transcriptionPrompt
		let setProgress: (Double) -> Void = { p in DispatchQueue.main.async { self.progress = p } }

		DispatchQueue.main.async { self.status = "Transcribing…"; self.progress = 0.05 }
		let them = try Transcriber.transcribe(wavPath: systemWav, model: model, language: lang, prompt: hint, speaker: "Them",
			progress: { setProgress(0.05 + $0 * 0.45) }, cancel: cancel, log: { _ in })
		let you = try Transcriber.transcribe(wavPath: micWav, model: model, language: lang, prompt: hint, speaker: "You",
			progress: { setProgress(0.50 + $0 * 0.40) }, cancel: cancel, log: { _ in })
		let transcript = Transcriber.diarizedMarkdown(them + you)

		if cancel.isCancelled { throw CancelledError() }
		var summary = ""
		if let engine = Self.engine(from: settings) {
			DispatchQueue.main.async { self.status = "Summarizing…"; self.progress = 0.92 }
			do { summary = try Summarizer.summarize(transcript: transcript, prompt: settings.currentPrompt(), engine: engine) }
			catch { DispatchQueue.main.async { self.status = "Summary skipped: \(error)" } }
		}
		return (transcript, summary)
	}

	private func finish(status: String) {
		DispatchQueue.main.async {
			self.busy = false
			self.progress = 1
			self.cancelToken = nil
			self.activeID = nil
			self.stopElapsedTimer()
			self.status = status
			self.store.reload(folder: self.settings.meetingsDirURL)
		}
	}

	// MARK: helpers

	private static func engine(from s: AppSettings) -> SummaryEngine? {
		switch s.summaryEngine {
		case "ollama": return .ollama(url: s.ollamaURL, model: s.ollamaModel)
		case "claude": return .claude(apiKey: s.claudeAPIKey, model: s.claudeModel)
		default: return nil
		}
	}

	private static func buildNote(title: String, date: String, audioBase: String, durationSeconds: Int, summary: String, transcript: String) -> String {
		let audioName = (audioBase as NSString).lastPathComponent
		var s = "---\ntype: meeting\ntags: [meeting]\ndate: \(date)\naudio: \(audioBase)\n"
		if durationSeconds > 0 { s += "duration: \(durationSeconds)\n" }
		s += "app_version: \(appVersion)\n"
		s += "---\n\n# \(title)\n\n"
		if !summary.isEmpty { s += summary + "\n\n" }
		s += "## Transcript\n\n" + (transcript.isEmpty ? "_(no speech detected)_" : transcript) + "\n"
		// Embed the audio so Obsidian shows inline players. The app hides this
		// section (it has its own access to the recordings).
		s += "\n## Audio\n\n**You (microphone)**\n\n![[\(audioName).mic.wav]]\n\n"
		s += "**Them (system audio)**\n\n![[\(audioName).system.wav]]\n"
		return s
	}

	/// Length (seconds) of a recording, from whichever track exists.
	private static func audioDurationSeconds(systemWav: String, micWav: String) -> Int {
		for p in [systemWav, micWav] {
			if let f = try? AVAudioFile(forReading: URL(fileURLWithPath: p)) {
				let secs = Double(f.length) / f.processingFormat.sampleRate
				if secs > 0 { return Int(secs.rounded()) }
			}
		}
		return 0
	}

	/// Find an existing note that links the given audio base - matches even if the
	/// note file was renamed during recording.
	static func existingNoteURL(audioBase: String, in dir: URL) -> URL? {
		let items = (try? FileManager.default.contentsOfDirectory(
			at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
		for url in items where url.pathExtension.lowercased() == "md" {
			let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
			if frontmatterValue("audio", in: content) == audioBase { return url }
		}
		return nil
	}

	/// Read a `key: value` line from a note's YAML frontmatter block.
	static func frontmatterValue(_ key: String, in content: String) -> String? {
		guard content.hasPrefix("---") else { return nil }
		var inBlock = false
		for (i, line) in content.components(separatedBy: "\n").enumerated() {
			if i == 0, line == "---" { inBlock = true; continue }
			if inBlock, line == "---" { break }
			if inBlock, line.hasPrefix("\(key):") {
				return line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
			}
		}
		return nil
	}

	private func startElapsedTimer() {
		procStart = Date()
		elapsed = "0s"
		remaining = ""
		procTimer?.invalidate()
		procTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			guard let self = self, let start = self.procStart else { return }
			let e = Date().timeIntervalSince(start)
			self.elapsed = Self.shortTime(e)
			// Extrapolate remaining from progress once there's enough signal to be
			// meaningful (the pipeline starts at 0.05 and ends at 1.0).
			let p = self.progress
			if p > 0.1, p < 0.99 {
				let rem = e / p - e
				self.remaining = rem > 1 ? "~\(Self.shortTime(rem)) left" : ""
			} else {
				self.remaining = ""
			}
		}
	}

	/// Compact duration like `45s`, `2m 05s`, `1h 03m`.
	private static func shortTime(_ seconds: TimeInterval) -> String {
		let s = max(0, Int(seconds.rounded()))
		if s < 60 { return "\(s)s" }
		if s < 3600 { return String(format: "%dm %02ds", s / 60, s % 60) }
		return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
	}

	private func stopElapsedTimer() {
		procTimer?.invalidate()
		procTimer = nil
		remaining = ""
	}

	private static func timestamp() -> String {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd HH-mm-ss"
		return f.string(from: Date())
	}
}