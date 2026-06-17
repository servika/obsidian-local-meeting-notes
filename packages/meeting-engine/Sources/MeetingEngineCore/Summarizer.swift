// Meeting summary + action items, from a transcript, via a local Ollama model
// or the Claude API. Both are synchronous (call off the main thread).

import Foundation

public enum SummaryEngine {
	case ollama(url: String, model: String)
	case claude(apiKey: String, model: String)
}

public enum Summarizer {
	public static let defaultPrompt = """
	You are summarizing a meeting transcript (lines are labeled You/Them). Respond in clean Markdown with exactly these sections and nothing else:

	## Summary
	A concise paragraph (3-5 sentences) covering purpose and outcome.

	## Action items
	- [ ] Each task, with the owner if mentioned.

	Transcript:
	{{transcript}}
	"""

	public static func summarize(transcript: String, prompt: String, engine: SummaryEngine) throws -> String {
		let filled = prompt.contains("{{transcript}}")
			? prompt.replacingOccurrences(of: "{{transcript}}", with: transcript)
			: "\(prompt)\n\n\(transcript)"
		switch engine {
		case let .ollama(url, model):
			return try ollama(filled, url: url, model: model)
		case let .claude(apiKey, model):
			return try claude(filled, apiKey: apiKey, model: model)
		}
	}

	// MARK: Ollama

	private static func ollama(_ prompt: String, url: String, model: String) throws -> String {
		guard !model.isEmpty else { throw SummaryError("no Ollama model set") }
		let endpoint = url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/generate"
		guard let u = URL(string: endpoint) else { throw SummaryError("bad Ollama URL: \(url)") }
		let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false]
		let data = try post(u, headers: ["Content-Type": "application/json"], json: body)
		guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw SummaryError("unexpected Ollama response")
		}
		if let err = obj["error"] as? String { throw SummaryError("Ollama: \(err)") }
		return (obj["response"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: Claude

	private static func claude(_ prompt: String, apiKey: String, model: String) throws -> String {
		guard !apiKey.isEmpty else { throw SummaryError("no Claude API key set") }
		guard let u = URL(string: "https://api.anthropic.com/v1/messages") else {
			throw SummaryError("bad Claude URL")
		}
		let body: [String: Any] = [
			"model": model,
			"max_tokens": 2048,
			"messages": [["role": "user", "content": prompt]],
		]
		let data = try post(u, headers: [
			"Content-Type": "application/json",
			"x-api-key": apiKey,
			"anthropic-version": "2023-06-01",
		], json: body)
		guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw SummaryError("unexpected Claude response")
		}
		if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
			throw SummaryError("Claude: \(msg)")
		}
		if (obj["stop_reason"] as? String) == "refusal" {
			throw SummaryError("Claude declined to summarize this content")
		}
		let blocks = obj["content"] as? [[String: Any]] ?? []
		let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: HTTP

	private static func post(_ url: URL, headers: [String: String], json: [String: Any]) throws -> Data {
		var req = URLRequest(url: url, timeoutInterval: 300)
		req.httpMethod = "POST"
		for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
		req.httpBody = try JSONSerialization.data(withJSONObject: json)

		let sem = DispatchSemaphore(value: 0)
		var result: Data?
		var failure: Error?
		var status = 0
		URLSession.shared.dataTask(with: req) { data, response, error in
			if let error = error { failure = error }
			else {
				status = (response as? HTTPURLResponse)?.statusCode ?? 0
				result = data
			}
			sem.signal()
		}.resume()
		sem.wait()

		if let failure = failure { throw failure }
		guard let result = result else { throw SummaryError("no response") }
		if status >= 400 {
			let snippet = String(data: result, encoding: .utf8)?.prefix(300) ?? ""
			throw SummaryError("HTTP \(status): \(snippet)")
		}
		return result
	}
}

public struct SummaryError: Error, CustomStringConvertible {
	public let message: String
	public init(_ message: String) { self.message = message }
	public var description: String { message }
}

// List installed Ollama models (for the Settings picker).
public enum Ollama {
	public static func installedModels(url: String) -> [String] {
		let endpoint = url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tags"
		guard let u = URL(string: endpoint) else { return [] }
		let sem = DispatchSemaphore(value: 0)
		var names: [String] = []
		URLSession.shared.dataTask(with: u) { data, _, _ in
			defer { sem.signal() }
			guard let data = data,
				let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				let models = obj["models"] as? [[String: Any]] else { return }
			names = models.compactMap { $0["name"] as? String }
		}.resume()
		_ = sem.wait(timeout: .now() + 3)
		return names.sorted()
	}
}