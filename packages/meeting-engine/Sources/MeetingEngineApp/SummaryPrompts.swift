import Foundation
import MeetingEngineCore

/// Baked-in default summary prompts, matched to a summary model by name.
///
/// Each model family responds best to a differently-phrased prompt (special
/// tokens, repetition of anti-preamble rules, etc.), so they live here together
/// rather than scattered through the settings code. A user can still override
/// the prompt per model (`AppSettings.promptOverrides`); these are the fallbacks.
enum SummaryPrompts {

	/// The default prompt for a given model name. Falls back to the generic
	/// `Summarizer.defaultPrompt` for models we don't special-case.
	static func defaultPrompt(for model: String) -> String {
		let m = model.lowercased()
		if m.contains("gpt-oss") { return gptOss }
		if m.contains("qwen") { return qwen }
		if m.contains("llama") { return llama }
		return Summarizer.defaultPrompt
	}

	/// Tuned for gpt-oss (harmony-style channel tags).
	static let gptOss = #"""
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
	static let llama = """
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
	static let qwen = """
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