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
	/// First reliable (elapsed, progress) sample once processing is underway, used
	/// to extrapolate "time left" from the live rate - accurate even on the first
	/// run, before the per-model estimate has calibrated.
	private var progressAnchor: (t: TimeInterval, p: Double)?
	/// Estimated total processing time for the current run (seconds); the UI shows
	/// it counting down. 0 = unknown.
	private var estimatedTotal: TimeInterval = 0
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
			status = "Choose a notes folder in Settings (⌘,) before recording."
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
				durationSeconds: 0, speakerCount: settings.speakerRecognitionEnabled ? settings.speakerCount : 0, summary: "", transcript: "_Recording in progress…_")
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

			let estModel = self.settings.modelPath(for: self.settings.language.isEmpty ? "auto" : self.settings.language)
			self.beginEstimate(audioSeconds: result.duration, model: estModel)
			let audioBase = "recordings/Meeting \(stamp)"
			// Follow a rename made during recording: find the placeholder note by
			// its audio link rather than reconstructing the original filename, so
			// we update that note instead of creating a duplicate.
			let noteURL = Self.existingNoteURL(audioBase: audioBase, in: meetingsDir)
				?? meetingsDir.appendingPathComponent("Meeting \(stamp).md")
			let title = noteURL.deletingPathExtension().lastPathComponent
			// New recordings seed their speaker count from the current setting; it's
			// then persisted per meeting and can be corrected before re-generating.
			let speakers = self.settings.speakerRecognitionEnabled ? self.settings.speakerCount : 0
			do {
				let (transcript, summary) = try self.transcribeAndSummarize(systemWav: result.systemURL.path, micWav: result.micURL.path, speakerCount: speakers, cancel: token)
				// Apply the audio-retention policy - but only when transcription ran,
				// so an audio-only recording is never compressed/deleted out from under
				// the user (the audio is the content in that case).
				let policy = self.settings.transcribeMeetings ? self.settings.audioRetention : "original"
				if policy != "original" { DispatchQueue.main.async { self.status = "Optimizing audio…" } }
				let audioExt = Self.finalizeAudio(systemWav: result.systemURL.path, micWav: result.micURL.path, policy: policy)
				let note = Self.buildNote(title: title, date: stamp, audioBase: audioBase, durationSeconds: Int(result.duration.rounded()), speakerCount: speakers, summary: summary, transcript: transcript, audioExt: audioExt)
				try note.write(to: noteURL, atomically: true, encoding: .utf8)
				Self.recordRate(audioSeconds: result.duration, model: estModel, processingSeconds: Date().timeIntervalSince(self.procStart ?? Date()))
				self.finish(status: "✅ Saved \(noteURL.lastPathComponent)" + Self.audioStatusSuffix(policy))
			} catch is CancelledError {
				// Keep the recording as a re-generatable note.
				let note = Self.buildNote(title: title, date: stamp, audioBase: audioBase, durationSeconds: Int(result.duration.rounded()), speakerCount: speakers, summary: "",
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
	/// `speakerCount` overrides the note's stored count (nil keeps it as-is).
	func regenerate(_ meeting: Meeting, speakerCount: Int? = nil) {
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
			// Audio may be the original WAV or a compressed M4A - use whichever exists.
			let audioExt = ["wav", "m4a"].first { e in
				FileManager.default.fileExists(atPath: meetingsDir.appendingPathComponent(audioBase + ".system." + e).path)
					|| FileManager.default.fileExists(atPath: meetingsDir.appendingPathComponent(audioBase + ".mic." + e).path)
			} ?? "wav"
			let systemWav = meetingsDir.appendingPathComponent(audioBase + ".system." + audioExt).path
			let micWav = meetingsDir.appendingPathComponent(audioBase + ".mic." + audioExt).path
			let dur = Int(Self.frontmatterValue("duration", in: content) ?? "") ?? Self.audioDurationSeconds(systemWav: systemWav, micWav: micWav)
			// An explicit override wins; otherwise keep whatever the note recorded.
			let speakers = self.settings.speakerRecognitionEnabled
				? (speakerCount ?? Int(Self.frontmatterValue("speakers", in: content) ?? "") ?? 0)
				: 0

			guard FileManager.default.fileExists(atPath: systemWav) || FileManager.default.fileExists(atPath: micWav) else {
				self.finish(status: "No saved audio found (it may have been removed after transcription).")
				return
			}
			let estModel = self.settings.modelPath(for: self.settings.language.isEmpty ? "auto" : self.settings.language)
			self.beginEstimate(audioSeconds: Double(dur), model: estModel)
			do {
				let (transcript, summary) = try self.transcribeAndSummarize(systemWav: systemWav, micWav: micWav, speakerCount: speakers, cancel: token)
				let note = Self.buildNote(title: title, date: date, audioBase: audioBase, durationSeconds: dur, speakerCount: speakers, summary: summary, transcript: transcript, audioExt: audioExt)
				try note.write(to: noteURL, atomically: true, encoding: .utf8)
				Self.recordRate(audioSeconds: Double(dur), model: estModel, processingSeconds: Date().timeIntervalSince(self.procStart ?? Date()))
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
	private func transcribeAndSummarize(systemWav: String, micWav: String, speakerCount: Int, cancel: CancelToken) throws -> (transcript: String, summary: String) {
		let lang = settings.language.isEmpty ? "auto" : settings.language
		let model = (settings.modelPath(for: lang) as NSString).expandingTildeInPath
		let hint = settings.transcriptionPrompt
		let setProgress: (Double) -> Void = { p in DispatchQueue.main.async { self.progress = p } }

		// Stage 1: transcription (opt-out). When off, we keep just the audio note.
		var transcript = ""
		if settings.transcribeMeetings {
			DispatchQueue.main.async { self.status = "Transcribing…"; self.progress = 0.05 }
			var them = try Transcriber.transcribe(wavPath: systemWav, model: model, language: lang, prompt: hint, speaker: "Them",
				progress: { setProgress(0.05 + $0 * 0.45) }, cancel: cancel, log: { _ in })
			let you = try Transcriber.transcribe(wavPath: micWav, model: model, language: lang, prompt: hint, speaker: "You",
				progress: { setProgress(0.50 + $0 * 0.38) }, cancel: cancel, log: { _ in })

			// Experimental: split the single "Them" into per-speaker labels by running
			// diarization on the system track and relabeling its segments by overlap.
			// Best-effort - on any failure we keep the plain "Them" transcript.
			if settings.speakerRecognitionEnabled, Diarizer.isAvailable() {
				DispatchQueue.main.async { self.status = "Identifying speakers…"; self.progress = 0.90 }
				do {
					let spans = try Diarizer.diarize(wavPath: systemWav, speakerCount: speakerCount, cancel: cancel, log: { _ in })
					them = Diarizer.relabel(them, using: spans)
				} catch is CancelledError {
					throw CancelledError()
				} catch {
					DispatchQueue.main.async { self.status = "Speaker recognition skipped: \(error)" }
				}
			}
			transcript = Transcriber.diarizedMarkdown(them + you)
		}

		if cancel.isCancelled { throw CancelledError() }

		// Stage 2: summary (opt-out). Needs a transcript and a configured engine.
		var summary = ""
		if settings.summarizeMeetings, !transcript.isEmpty, let engine = Self.engine(from: settings) {
			DispatchQueue.main.async { self.status = "Summarizing…"; self.progress = 0.92 }
			let prompt = settings.currentPrompt().replacingOccurrences(of: "{{language}}", with: Self.languageName(lang))
			do { summary = try Summarizer.summarize(transcript: transcript, prompt: prompt, engine: engine) }
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

	/// Human-readable language for the `{{language}}` prompt slot. "auto" (or
	/// anything unknown) tells the model to match the transcript's language.
	private static func languageName(_ code: String) -> String {
		switch code {
		case "uk": return "Ukrainian"
		case "en": return "English"
		default: return "the same language as the transcript"
		}
	}

	private static func engine(from s: AppSettings) -> SummaryEngine? {
		switch s.summaryEngine {
		case "ollama": return .ollama(url: s.ollamaURL, model: s.ollamaModel)
		case "claude": return .claude(apiKey: s.claudeAPIKey, model: s.claudeModel)
		default: return nil
		}
	}

	/// `audioExt` is the extension of the kept tracks ("wav" or "m4a"), or nil when
	/// the audio was deleted after transcription.
	private static func buildNote(title: String, date: String, audioBase: String, durationSeconds: Int, speakerCount: Int = 0, summary: String, transcript: String, audioExt: String? = "wav") -> String {
		let audioName = (audioBase as NSString).lastPathComponent
		var s = "---\ntype: meeting\ntags: [meeting]\ndate: \(date)\naudio: \(audioBase)\n"
		if durationSeconds > 0 { s += "duration: \(durationSeconds)\n" }
		if speakerCount >= 2 { s += "speakers: \(speakerCount)\n" }
		s += "app_version: \(appVersion)\n"
		s += "---\n\n# \(title)\n\n"
		if !summary.isEmpty { s += summary + "\n\n" }
		s += "## Transcript\n\n" + (transcript.isEmpty ? "_(no speech detected)_" : transcript) + "\n"
		// Embed the audio so Obsidian shows inline players. The app hides this
		// section (it has its own access to the recordings).
		s += "\n## Audio\n\n"
		if let ext = audioExt {
			s += "**You (microphone)**\n\n![[\(audioName).mic.\(ext)]]\n\n"
			s += "**Them (system audio)**\n\n![[\(audioName).system.\(ext)]]\n"
		} else {
			s += "_Audio removed after transcription to save space._\n"
		}
		return s
	}

	// MARK: audio retention

	/// Apply the audio-retention policy after a successful transcription. Returns
	/// the extension to embed ("wav"/"m4a"), or nil when the audio was deleted.
	private static func finalizeAudio(systemWav: String, micWav: String, policy: String) -> String? {
		let fm = FileManager.default
		switch policy {
		case "delete":
			for p in [systemWav, micWav] { try? fm.removeItem(atPath: p) }
			return nil
		case "compressed":
			var allOK = true
			for wav in [systemWav, micWav] where fm.fileExists(atPath: wav) {
				let m4a = (wav as NSString).deletingPathExtension + ".m4a"
				if compressToM4A(wav: wav, m4a: m4a) {
					try? fm.removeItem(atPath: wav)
				} else {
					allOK = false
				}
			}
			return allOK ? "m4a" : "wav" // fall back to keeping WAV if encoding failed
		default: // "original"
			return "wav"
		}
	}

	/// Transcode a WAV to a small AAC `.m4a` (speech-quality bitrate) via afconvert.
	private static func compressToM4A(wav: String, m4a: String) -> Bool {
		let p = Process()
		p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
		p.arguments = ["-f", "m4af", "-d", "aac", "-b", "48000", wav, m4a]
		p.standardOutput = Pipe(); p.standardError = Pipe()
		do { try p.run() } catch { return false }
		p.waitUntilExit()
		return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: m4a)
	}

	private static func audioStatusSuffix(_ policy: String) -> String {
		switch policy {
		case "compressed": return " · audio compressed"
		case "delete": return " · audio removed"
		default: return ""
		}
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
		progressAnchor = nil
		elapsed = "0s"
		remaining = ""
		procTimer?.invalidate()
		procTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			guard let self = self, let start = self.procStart else { return }
			let e = Date().timeIntervalSince(start)
			self.elapsed = Self.shortTime(e)
			self.remaining = self.estimateRemaining(elapsed: e)
		}
	}

	/// "Time left" string. Once real progress is flowing we extrapolate from the
	/// observed rate (works on the very first run, no learned estimate needed);
	/// before that we fall back to the up-front per-model estimate.
	private func estimateRemaining(elapsed e: TimeInterval) -> String {
		let p = progress
		// Anchor on the first meaningful progress sample (past the initial jump to
		// 5%), then extrapolate the remaining work from the rate since the anchor.
		if p > 0.07, p < 0.99 {
			if let a = progressAnchor, p > a.p + 0.01, e > a.t {
				let rate = (p - a.p) / (e - a.t)        // progress per second
				let rem = (1 - p) / max(rate, 0.0001)
				return rem > 2 ? "~\(Self.shortTime(rem)) left" : "finishing…"
			}
			if progressAnchor == nil { progressAnchor = (e, p) }
		}
		// Fallback: up-front estimate (seeded by model size, calibrated over runs).
		if estimatedTotal > 0 {
			let rem = estimatedTotal - e
			return rem > 2 ? "~\(Self.shortTime(rem)) left" : "finishing…"
		}
		return ""
	}

	// MARK: processing-time estimate (learned per transcription model)

	/// Set the up-front estimate from the audio length and the model's learned
	/// (or seeded) end-to-end processing rate.
	private func beginEstimate(audioSeconds: Double, model: String) {
		let est = audioSeconds * Self.processingRate(forModel: model)
		DispatchQueue.main.async { self.estimatedTotal = est }
	}

	/// Update the learned rate (processing seconds per audio second) for a model.
	private static func recordRate(audioSeconds: Double, model: String, processingSeconds: Double) {
		guard audioSeconds > 1, processingSeconds > 0 else { return }
		let key = rateKey(model)
		let new = processingSeconds / audioSeconds
		let prev = UserDefaults.standard.double(forKey: key)
		UserDefaults.standard.set(prev > 0 ? prev * 0.6 + new * 0.4 : new, forKey: key)
	}

	private static func processingRate(forModel model: String) -> Double {
		let stored = UserDefaults.standard.double(forKey: rateKey(model))
		if stored > 0 { return stored }
		let m = model.lowercased()
		if m.contains("large") { return 1.5 }
		if m.contains("medium") { return 1.0 }
		if m.contains("small") { return 0.5 }
		if m.contains("tiny") { return 0.1 }
		return 0.25 // base, or unknown
	}

	private static func rateKey(_ model: String) -> String {
		"procRate." + (model as NSString).lastPathComponent
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
		estimatedTotal = 0
	}

	private static func timestamp() -> String {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd HH-mm-ss"
		return f.string(from: Date())
	}
}