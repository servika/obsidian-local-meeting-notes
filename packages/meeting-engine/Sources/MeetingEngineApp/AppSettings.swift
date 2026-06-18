import Foundation
import MeetingEngineCore

/// Persisted app settings (UserDefaults-backed).
final class AppSettings: ObservableObject {
	private let d = UserDefaults.standard

	@Published var vaultPath: String { didSet { d.set(vaultPath, forKey: "vaultPath") } }
	@Published var meetingsFolder: String { didSet { d.set(meetingsFolder, forKey: "meetingsFolder") } }
	@Published var whisperModelPath: String { didSet { d.set(whisperModelPath, forKey: "whisperModelPath") } }
	@Published var language: String { didSet { d.set(language, forKey: "language") } }
	@Published var summaryEngine: String { didSet { d.set(summaryEngine, forKey: "summaryEngine") } } // none|ollama|claude
	@Published var ollamaURL: String { didSet { d.set(ollamaURL, forKey: "ollamaURL") } }
	@Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
	@Published var claudeAPIKey: String { didSet { d.set(claudeAPIKey, forKey: "claudeAPIKey") } }
	@Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
	/// Per-model prompt overrides (keyed by model name). Falls back to the baked
	/// default for that model when there's no override.
	@Published var promptOverrides: [String: String] { didSet { d.set(promptOverrides, forKey: "promptOverrides") } }

	init() {
		vaultPath = d.string(forKey: "vaultPath") ?? ""
		meetingsFolder = d.string(forKey: "meetingsFolder") ?? "Meetings"
		whisperModelPath = d.string(forKey: "whisperModelPath") ?? "~/models/ggml-base.bin"
		language = d.string(forKey: "language") ?? "auto"
		summaryEngine = d.string(forKey: "summaryEngine") ?? "ollama"
		ollamaURL = d.string(forKey: "ollamaURL") ?? "http://localhost:11434"
		ollamaModel = d.string(forKey: "ollamaModel") ?? ""
		claudeAPIKey = d.string(forKey: "claudeAPIKey") ?? ""
		claudeModel = d.string(forKey: "claudeModel") ?? "claude-opus-4-8"
		var overrides = (d.dictionary(forKey: "promptOverrides") as? [String: String]) ?? [:]
		// Migrate a legacy single prompt onto the current model.
		if overrides.isEmpty, let legacy = d.string(forKey: "summaryPrompt"), !legacy.isEmpty {
			let key = (d.string(forKey: "summaryEngine") == "claude") ? (d.string(forKey: "claudeModel") ?? "claude-opus-4-8") : (d.string(forKey: "ollamaModel") ?? "")
			if !key.isEmpty { overrides[key] = legacy }
		}
		promptOverrides = overrides
	}

	/// `<vault>/<meetingsFolder>` - nil until a vault is configured.
	var meetingsDirURL: URL? {
		let vp = (vaultPath as NSString).expandingTildeInPath
		guard !vp.isEmpty else { return nil }
		return URL(fileURLWithPath: vp).appendingPathComponent(meetingsFolder, isDirectory: true)
	}

	/// The model the summary will use (depends on the chosen engine).
	var activeSummaryModel: String {
		summaryEngine == "claude" ? claudeModel : ollamaModel
	}

	func currentPrompt() -> String {
		if let p = promptOverrides[activeSummaryModel], !p.isEmpty { return p }
		return Self.defaultPrompt(for: activeSummaryModel)
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

	// MARK: baked-in default prompts (matched by model name)

	static func defaultPrompt(for model: String) -> String {
		let m = model.lowercased()
		if m.contains("gpt-oss") { return gptOssPrompt }
		if m.contains("llama") { return llamaPrompt }
		return Summarizer.defaultPrompt
	}

	/// Tuned for gpt-oss (harmony-style channel tags).
	static let gptOssPrompt = #"""
	<|system|>
	You extract structured meeting notes from transcripts. You are precise and never invent information that is not in the transcript.

	Rules:
	1. Output ONLY valid Markdown. No preamble, no explanation, no sign-off.
	2. Use EXACTLY four sections, in this order: ## Short summary, ## Summary, ## Topics discussed, ## Action items.
	3. Short summary = 1-2 sentences capturing the single most important outcome.
	4. Summary = one or two short paragraphs stating who met, the main topics, key decisions, and the outcome.
	5. Topics discussed = for each distinct topic or block raised, a "### " subheading naming the topic, then 1-3 bullet points of what was said or decided about it.
	6. Action items = a checkbox list. Each line: "- [ ] <task> - <owner>" (use "Owner TBD" if no one was assigned). If there are zero action items, write "- None identified."
	7. "You" = the user who recorded the transcript. "Them" = the other participant(s).
	8. Do NOT add sections, headers, or content beyond what is specified above.

	<|user|>
	Transcript:
	"""
	{{transcript}}
	"""

	Summarize this meeting. Follow the rules exactly.
	"""#

	/// Default for Llama-family models (plain instruction style). Replace with
	/// your tuned version if you have one.
	static let llamaPrompt = """
	You are an expert meeting-notes assistant. From the transcript below (lines are labeled You/Them), produce clean Markdown with EXACTLY these three sections, in this order, and nothing else.

	## Short summary
	One or two sentences with the single most important outcome.

	## Summary
	One or two short paragraphs: who met, the main topics, key decisions, and the outcome.

	## Topics discussed
	For each distinct topic or block raised, a "### " subheading naming the topic, then 1-3 bullet points of what was said or decided about it.

	## Action items
	- [ ] <task> - <owner> (use "Owner TBD" if unassigned). If there are none, write "- None identified."

	Do not invent anything that is not in the transcript. No preamble, no sign-off.

	Transcript:
	{{transcript}}
	"""
}