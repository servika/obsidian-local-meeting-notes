import Foundation

/// Persisted app settings (UserDefaults-backed).
final class AppSettings: ObservableObject {
	private let d = UserDefaults.standard

	@Published var vaultPath: String { didSet { d.set(vaultPath, forKey: "vaultPath") } }
	@Published var meetingsFolder: String { didSet { d.set(meetingsFolder, forKey: "meetingsFolder") } }
	@Published var whisperModelPath: String { didSet { d.set(whisperModelPath, forKey: "whisperModelPath") } }
	@Published var language: String { didSet { d.set(language, forKey: "language") } }
	/// Suggest starting a recording when another app starts using the mic.
	@Published var suggestOnMeetingDetected: Bool { didSet { d.set(suggestOnMeetingDetected, forKey: "suggestOnMeetingDetected") } }
	/// Optional initial prompt passed to whisper to bias spelling/vocabulary
	/// (participant names, product/company terms, language). Improves accuracy.
	@Published var transcriptionPrompt: String { didSet { d.set(transcriptionPrompt, forKey: "transcriptionPrompt") } }
	/// Master switch for in-development R&D features. Off by default so the
	/// general experience is unaffected; individual experiments are only visible
	/// and active when this is on.
	@Published var experimentalMode: Bool { didSet { d.set(experimentalMode, forKey: "experimentalMode") } }
	/// Per-flag on/off state for R&D features (keyed by `FeatureFlag.rawValue`).
	/// Read via `isEnabled(_:)` / `flagValue(_:)` (see FeatureFlags.swift).
	@Published var featureFlags: [String: Bool] { didSet { d.set(featureFlags, forKey: "featureFlags") } }
	/// Default number of remote speakers for a new recording (0 = Auto-estimate).
	/// Stored per meeting in the note's `speakers:` frontmatter; this is the seed.
	@Published var speakerCount: Int { didSet { d.set(speakerCount, forKey: "speakerCount") } }
	/// Pipeline stage toggles - let the user run only the steps they want.
	@Published var transcribeMeetings: Bool { didSet { d.set(transcribeMeetings, forKey: "transcribeMeetings") } }
	@Published var summarizeMeetings: Bool { didSet { d.set(summarizeMeetings, forKey: "summarizeMeetings") } }
	/// What to do with the recorded audio after a successful transcription:
	/// "original" (keep WAV), "compressed" (AAC m4a, default), or "delete" (text only).
	@Published var audioRetention: String { didSet { d.set(audioRetention, forKey: "audioRetention") } }
	@Published var summaryEngine: String { didSet { d.set(summaryEngine, forKey: "summaryEngine") } } // ollama|claude
	@Published var ollamaURL: String { didSet { d.set(ollamaURL, forKey: "ollamaURL") } }
	@Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
	@Published var claudeAPIKey: String { didSet { d.set(claudeAPIKey, forKey: "claudeAPIKey") } }
	@Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
	/// Per-model prompt overrides (keyed by model name). Falls back to the baked
	/// default for that model when there's no override.
	@Published var promptOverrides: [String: String] { didSet { d.set(promptOverrides, forKey: "promptOverrides") } }
	/// Per-language whisper model overrides (keyed by language code, e.g. "uk").
	/// Falls back to `whisperModelPath` when there's no override for a language.
	@Published var modelByLanguage: [String: String] { didSet { d.set(modelByLanguage, forKey: "modelByLanguage") } }

	init() {
		vaultPath = d.string(forKey: "vaultPath") ?? ""
		meetingsFolder = d.string(forKey: "meetingsFolder") ?? "Meetings"
		whisperModelPath = d.string(forKey: "whisperModelPath") ?? "~/models/ggml-base.bin"
		language = d.string(forKey: "language") ?? "auto"
		suggestOnMeetingDetected = (d.object(forKey: "suggestOnMeetingDetected") as? Bool) ?? true
		transcriptionPrompt = d.string(forKey: "transcriptionPrompt") ?? ""
		experimentalMode = (d.object(forKey: "experimentalMode") as? Bool) ?? false
		var flags = (d.dictionary(forKey: "featureFlags") as? [String: Bool]) ?? [:]
		// Migrate the standalone legacy `recognizeSpeakers` bool into the flag set.
		if let legacy = d.object(forKey: "recognizeSpeakers") as? Bool {
			if flags[FeatureFlag.speakerRecognition.rawValue] == nil { flags[FeatureFlag.speakerRecognition.rawValue] = legacy }
			d.removeObject(forKey: "recognizeSpeakers")
		}
		featureFlags = flags
		speakerCount = d.integer(forKey: "speakerCount") // 0 (Auto) when unset
		summaryEngine = d.string(forKey: "summaryEngine") ?? "ollama"
		audioRetention = d.string(forKey: "audioRetention") ?? "compressed"
		transcribeMeetings = (d.object(forKey: "transcribeMeetings") as? Bool) ?? true
		// Migrate the legacy "None" summary engine to the explicit Summarize toggle:
		// a stored toggle wins; otherwise summary is on unless the engine was "none".
		summarizeMeetings = (d.object(forKey: "summarizeMeetings") as? Bool) ?? (d.string(forKey: "summaryEngine") != "none")
		ollamaURL = d.string(forKey: "ollamaURL") ?? "http://localhost:11434"
		ollamaModel = d.string(forKey: "ollamaModel") ?? ""
		claudeAPIKey = d.string(forKey: "claudeAPIKey") ?? ""
		claudeModel = d.string(forKey: "claudeModel") ?? "claude-opus-4-8"
		promptOverrides = (d.dictionary(forKey: "promptOverrides") as? [String: String]) ?? [:]
		// Drop a stale legacy single prompt if present. We no longer migrate it onto
		// a model - it shadowed the (now much better) baked defaults, so an old
		// 2-section prompt kept overriding new ones. Per-model prompts live in
		// `promptOverrides` and are only set when the user edits a prompt.
		d.removeObject(forKey: "summaryPrompt")
		modelByLanguage = (d.dictionary(forKey: "modelByLanguage") as? [String: String]) ?? [:]
		// Now that all stored properties are set, finish the "None"->toggle migration.
		if summaryEngine == "none" { summaryEngine = "ollama" }
	}

	/// The whisper model to use for a given language code: a per-language
	/// override if one is set, otherwise the default `whisperModelPath`.
	///
	/// Under "auto" the user hasn't named a language, so an override keyed on a
	/// real code (e.g. "uk" -> large-v3-turbo) would otherwise be silently skipped
	/// and we'd fall back to the weaker default model - which produces garbled,
	/// hallucinated transcripts on non-English audio. When exactly one override is
	/// configured, honor it for "auto" too; that's almost always the model the user
	/// wants. With several overrides we can't disambiguate, so keep the default.
	func modelPath(for language: String) -> String {
		if let override = modelByLanguage[language], !override.isEmpty { return override }
		if language == "auto" || language.isEmpty {
			let overrides = modelByLanguage.filter { !$0.value.isEmpty }
			if overrides.count == 1, let only = overrides.first { return only.value }
		}
		return whisperModelPath
	}

	func setModel(_ path: String, for language: String) {
		var m = modelByLanguage
		let trimmed = path.trimmingCharacters(in: .whitespaces)
		if trimmed.isEmpty { m.removeValue(forKey: language) } else { m[language] = trimmed }
		modelByLanguage = m
	}

	func removeModel(for language: String) {
		var m = modelByLanguage
		m.removeValue(forKey: language)
		modelByLanguage = m
	}

	/// `<vault>/<meetingsFolder>` - nil until a vault is configured.
	var meetingsDirURL: URL? {
		let vp = (vaultPath as NSString).expandingTildeInPath
		guard !vp.isEmpty else { return nil }
		return URL(fileURLWithPath: vp).appendingPathComponent(meetingsFolder, isDirectory: true)
	}

	/// Speaker recognition is active only when both the experiment master switch
	/// and its flag are on. Convenience alias for the most-used flag.
	var speakerRecognitionEnabled: Bool { isEnabled(.speakerRecognition) }

	// MARK: stage availability

	/// Whether a usable whisper model exists for the current language. When false,
	/// transcription can't run (the toggle is shown but disabled).
	var transcriptionAvailable: Bool {
		let lang = language.isEmpty ? "auto" : language
		let p = (modelPath(for: lang) as NSString).expandingTildeInPath
		return !p.isEmpty && FileManager.default.fileExists(atPath: p)
	}

	var transcriptionUnavailableReason: String? {
		transcriptionAvailable ? nil : "No whisper model installed - download one in the Transcription tab."
	}

	/// Whether the chosen summary engine is fully configured (a local model is
	/// selected, or a Claude API key is set). Summary also requires transcription.
	var summaryAvailable: Bool { summaryUnavailableReason == nil }

	var summaryUnavailableReason: String? {
		switch summaryEngine {
		case "ollama":
			return ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty
				? "No local model selected - install one (e.g. `ollama pull \("qwen2.5:7b")`) and pick it in the Summary tab."
				: nil
		case "claude":
			return claudeAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
				? "Add your Claude API key in the Summary tab."
				: nil
		default:
			return "Choose a summary engine in the Summary tab."
		}
	}

	/// The model the summary will use (depends on the chosen engine).
	var activeSummaryModel: String {
		summaryEngine == "claude" ? claudeModel : ollamaModel
	}

	func currentPrompt() -> String {
		if let p = promptOverrides[activeSummaryModel], !p.isEmpty { return p }
		return SummaryPrompts.defaultPrompt(for: activeSummaryModel)
	}

	func setCurrentPrompt(_ p: String) {
		var o = promptOverrides
		o[activeSummaryModel] = p
		promptOverrides = o
	}

	func resetCurrentPrompt() {
		var o = promptOverrides
		o.removeValue(forKey: activeSummaryModel)
		promptOverrides = o
	}

	var currentPromptIsCustom: Bool {
		promptOverrides[activeSummaryModel] != nil
	}
}