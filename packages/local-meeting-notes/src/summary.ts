import { requestUrl } from "obsidian";

export interface SummaryOptions {
	/** Base URL of the local Ollama instance, e.g. http://localhost:11434 */
	url: string;
	/** Model name as listed by `ollama list`, e.g. gpt-oss:20b */
	model: string;
	/** Prompt template; the literal `{{transcript}}` is replaced with the text. */
	promptTemplate: string;
}

/**
 * Summarize a transcript with a local LLM via Ollama's generate API. This is the
 * only outbound request the plugin makes, it targets localhost, and it only runs
 * when the user has explicitly enabled summaries. Nothing leaves the machine.
 */
export async function summarize(transcript: string, opts: SummaryOptions): Promise<string> {
	if (!opts.model) {
		throw new Error("no Ollama model set - choose one in plugin settings");
	}

	const prompt = opts.promptTemplate.includes("{{transcript}}")
		? opts.promptTemplate.replace("{{transcript}}", transcript)
		: `${opts.promptTemplate}\n\n${transcript}`;

	const endpoint = opts.url.replace(/\/+$/, "") + "/api/generate";

	const res = await requestUrl({
		url: endpoint,
		method: "POST",
		contentType: "application/json",
		body: JSON.stringify({ model: opts.model, prompt, stream: false }),
		throw: false,
	});

	if (res.status !== 200) {
		const detail = (res.text || "").slice(0, 300);
		throw new Error(`Ollama returned ${res.status}. Is it running (\`ollama serve\`)? ${detail}`);
	}

	const data = res.json as { response?: string; error?: string };
	if (data.error) throw new Error(`Ollama error: ${data.error}`);
	return (data.response ?? "").trim();
}