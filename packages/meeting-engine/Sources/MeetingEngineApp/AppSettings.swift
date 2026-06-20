import Foundation
import MeetingEngineCore

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
	@Published var summaryEngine: String { didSet { d.set(summaryEngine, forKey: "summaryEngine") } } // none|ollama|claude
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
		summaryEngine = d.string(forKey: "summaryEngine") ?? "ollama"
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
	}

	/// The whisper model to use for a given language code: a per-language
	/// override if one is set, otherwise the default `whisperModelPath`.
	func modelPath(for language: String) -> String {
		if let override = modelByLanguage[language], !override.isEmpty { return override }
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
		if m.contains("qwen") { return qwenPrompt }
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
	5. Topics discussed = for each distinct topic or block raised, a "### " subheading naming the topic, then 1-3 short paragraphs and bullet points describing what was said or decided about it.
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

	/// Tuned for Llama-family models (llama3.x). Plain-instruction style - Ollama
	/// applies the model's own chat template, so no special tokens are needed.
	/// Llama tends to add chatty preambles, so the no-preamble rule is repeated.
	static let llamaPrompt = """
	You are an expert meeting-notes assistant. You are given a meeting transcript whose lines are labeled "You" (the person who recorded the meeting) and "Them" (the other participant(s)).

	Produce clean Markdown with EXACTLY these four sections, in this exact order, using these exact headings:

	## Short summary
	One or two sentences capturing the single most important outcome of the meeting.

	## Summary
	One or two short paragraphs covering who met, the main topics, the key decisions, and the outcome.

	## Topics discussed
	For each distinct topic raised, write a "### " subheading naming the topic, then 1-2 short paragraphs (use bullet points where it helps) describing what was said or decided about it. Cover every significant topic; do not merge unrelated topics.

	## Action items
	A checkbox list. Each line: "- [ ] <task> - <owner>" (use "Owner TBD" if no one was assigned). If there are no action items, write exactly "- None identified."

	Strict rules:
	- Use only information present in the transcript. Never invent names, numbers, dates, decisions, or tasks.
	- Output ONLY the four sections above. No preamble, no "Here is...", no notes, no sign-off.
	- Keep it concise and factual.

	Transcript:
	{{transcript}}
	"""

	/// Tuned for Qwen models (qwen2.5 / qwen3). Qwen is strong at structured
	/// output on clean transcripts but, on fragmented speech-recognition text, it
	/// tends to refuse or go chatty - so the rules forbid that explicitly.
	static let qwenPrompt = """
	You write meeting notes from a transcript whose lines are labeled "You" (the person who recorded it) and "Them" (the other participant(s)). It is speech-recognition output, so it may be fragmented or informal - work with whatever is there.

	Output Markdown with ALL FOUR of these headings, in this exact order and spelling. You MUST include every heading, even ## Topics discussed - never omit it:

	## Short summary
	1-2 sentences with the single most important outcome.

	## Summary
	1-2 short paragraphs covering the whole meeting - beginning, middle, and end, not just the last part.

	## Topics discussed
	For EACH distinct topic, a "### " subheading naming the topic, then 2-5 sentences about what was said or decided. Include every significant topic from the entire meeting. Keep amounts (e.g. $250), limits, dates, and names exactly as in the transcript.

	## Action items
	A checkbox list: "- [ ] <task> - <owner> - <deadline>" (use "Owner TBD" if unassigned; include a deadline only if explicitly stated). One line per real commitment. If there are genuinely none, write a single "- None identified." line and nothing else.

	Rules:
	- NEVER refuse, ask for clarification, or add any preamble or closing remarks. Output only the four sections.
	- Keep the four section headings EXACTLY in English as written above (## Short summary, ## Summary, ## Topics discussed, ## Action items). Write the body text in {{language}}.
	- Use names exactly as spoken; never translate or invent names, numbers, amounts, or dates.

	Transcript:
	{{transcript}}
	"""
}