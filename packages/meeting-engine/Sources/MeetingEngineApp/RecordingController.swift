import Foundation
import MeetingEngineCore

/// Drives record → stop → transcribe → summarize → save-to-vault, exposing
/// observable state for the UI.
final class RecordingController: ObservableObject {
	@Published var isRecording = false
	@Published var busy = false
	@Published var status = "Ready."
	@Published var systemLevel: Float = 0
	@Published var micLevel: Float = 0

	private var recorder: MeetingRecorder?
	private var stamp = ""
	private let settings: AppSettings
	private let store: MeetingStore

	init(settings: AppSettings, store: MeetingStore) {
		self.settings = settings
		self.store = store
	}

	func toggle() { isRecording ? stop() : start() }

	func start() {
		guard let meetingsDir = settings.meetingsDirURL else {
			status = "Set your Obsidian vault in Settings (⌘,)."
			return
		}
		let recordingsDir = meetingsDir.appendingPathComponent("recordings", isDirectory: true)
		try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

		stamp = Self.timestamp()
		let outBase = recordingsDir.appendingPathComponent("Meeting \(stamp)").path
		let r = MeetingRecorder(log: { [weak self] msg in
			DispatchQueue.main.async { self?.status = msg }
		})
		r.onLevel = { [weak self] s, m in
			DispatchQueue.main.async { self?.systemLevel = s; self?.micLevel = m }
		}
		do {
			try r.start(outBase: outBase, appName: nil)
			recorder = r
			isRecording = true
			status = "Recording… click Stop when the meeting ends."
		} catch {
			status = "Couldn't start: \(error)"
		}
	}

	func stop() {
		guard let r = recorder else { return }
		isRecording = false
		busy = true
		status = "Finishing recording…"
		let settings = self.settings
		let store = self.store
		let stamp = self.stamp
		guard let meetingsDir = settings.meetingsDirURL else { busy = false; return }

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let result = r.stop()
			DispatchQueue.main.async { self?.systemLevel = 0; self?.micLevel = 0; self?.status = "Transcribing…" }

			let model = (settings.whisperModelPath as NSString).expandingTildeInPath
			do {
				let them = try Transcriber.transcribe(wavPath: result.systemURL.path, model: model, speaker: "Them", log: { _ in })
				let you = try Transcriber.transcribe(wavPath: result.micURL.path, model: model, speaker: "You", log: { _ in })
				let transcript = Transcriber.diarizedMarkdown(them + you)

				var summary = ""
				if let engine = Self.engine(from: settings) {
					DispatchQueue.main.async { self?.status = "Summarizing…" }
					do { summary = try Summarizer.summarize(transcript: transcript, prompt: settings.summaryPrompt, engine: engine) }
					catch { DispatchQueue.main.async { self?.status = "Summary skipped: \(error)" } }
				}

				let note = Self.buildNote(stamp: stamp, summary: summary, transcript: transcript)
				let noteURL = meetingsDir.appendingPathComponent("Meeting \(stamp).md")
				try note.write(to: noteURL, atomically: true, encoding: .utf8)

				DispatchQueue.main.async {
					self?.recorder = nil
					self?.busy = false
					self?.status = "✅ Saved \(noteURL.lastPathComponent)"
					store.reload(folder: settings.meetingsDirURL)
				}
			} catch {
				DispatchQueue.main.async {
					self?.recorder = nil
					self?.busy = false
					self?.status = "Failed: \(error)"
				}
			}
		}
	}

	private static func engine(from s: AppSettings) -> SummaryEngine? {
		switch s.summaryEngine {
		case "ollama": return .ollama(url: s.ollamaURL, model: s.ollamaModel)
		case "claude": return .claude(apiKey: s.claudeAPIKey, model: s.claudeModel)
		default: return nil
		}
	}

	private static func buildNote(stamp: String, summary: String, transcript: String) -> String {
		var s = "---\ntype: meeting\ndate: \(stamp)\n---\n\n# Meeting \(stamp)\n\n"
		if !summary.isEmpty { s += summary + "\n\n" }
		s += "## Transcript\n\n" + (transcript.isEmpty ? "_(no speech detected)_" : transcript) + "\n"
		return s
	}

	private static func timestamp() -> String {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd HH-mm-ss"
		return f.string(from: Date())
	}
}