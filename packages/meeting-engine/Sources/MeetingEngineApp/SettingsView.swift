import SwiftUI
import AppKit
import MeetingEngineCore

struct SettingsView: View {
	@EnvironmentObject var settings: AppSettings
	@StateObject private var downloader = ModelDownloader()
	@State private var ollamaModels: [String] = []
	@State private var modelToDownload = "base"
	@State private var overrideLang = "uk"

	static var appVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
	}

	private var modelExists: Bool {
		modelFileExists(settings.whisperModelPath)
	}

	private func modelFileExists(_ path: String) -> Bool {
		let p = (path as NSString).expandingTildeInPath
		return !p.isEmpty && FileManager.default.fileExists(atPath: p)
	}

	/// Language codes that currently have a per-language model override, sorted.
	private var overrideLanguages: [String] {
		settings.modelByLanguage.keys.sorted()
	}

	/// Selectable languages (excluding "auto" and ones already overridden).
	private var unsetLanguages: [(code: String, name: String)] {
		meetingLanguages.filter { $0.code != "auto" && settings.modelByLanguage[$0.code] == nil }
	}

	private func languageName(_ code: String) -> String {
		meetingLanguages.first { $0.code == code }?.name ?? code
	}

	/// Human-readable size / speed / accuracy guidance for a downloadable model.
	/// `.en` variants are English-only and shouldn't be used for Ukrainian/auto.
	private func modelInfo(_ model: String) -> String {
		switch model {
		case "tiny":      return "≈75 MB · fastest, lowest accuracy. Multilingual."
		case "tiny.en":   return "≈75 MB · fastest, lowest accuracy. English only."
		case "base":      return "≈142 MB · fast, basic accuracy. Multilingual. Good default."
		case "base.en":   return "≈142 MB · fast, basic accuracy. English only."
		case "small":     return "≈466 MB · good balance of speed and accuracy. Multilingual."
		case "small.en":  return "≈466 MB · good balance of speed and accuracy. English only."
		case "medium":    return "≈1.5 GB · high accuracy, slower. Multilingual."
		case "medium.en": return "≈1.5 GB · high accuracy, slower. English only."
		case "large-v3":  return "≈3.1 GB · best accuracy, slowest. Multilingual - best for Ukrainian."
		case "large-v3-turbo": return "≈1.6 GB · near-large accuracy, much faster. Multilingual - great Ukrainian/speed balance."
		default:          return "Whisper ggml model."
		}
	}

	/// Whisper ggml models present in ~/models, as (display name, full path),
	/// e.g. ("large-v3", "/Users/me/models/ggml-large-v3.bin").
	private var localModels: [(name: String, path: String)] {
		let dir = ("~/models" as NSString).expandingTildeInPath
		let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
		return files
			.filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
			.map { (name: String($0.dropFirst(5).dropLast(4)),
				path: (dir as NSString).appendingPathComponent($0)) }
			.sorted { $0.name < $1.name }
	}

	/// Dropdown options for a per-language model: the downloaded models, plus the
	/// currently-stored path if it isn't among them (so a missing model still shows).
	private func modelOptions(including current: String) -> [(name: String, path: String)] {
		var opts = localModels
		if !current.isEmpty, !opts.contains(where: { $0.path == current }) {
			opts.insert((name: (current as NSString).lastPathComponent + " (missing)", path: current), at: 0)
		}
		return opts
	}

	var body: some View {
		TabView {
		Form {
			Section("Storage (Obsidian vault)") {
				HStack {
					TextField("Vault folder", text: $settings.vaultPath)
					Button("Choose…", action: chooseVault)
				}
				TextField("Meetings subfolder", text: $settings.meetingsFolder)
			}

			Section("Recording") {
				Toggle("Suggest recording when a meeting is detected", isOn: $settings.suggestOnMeetingDetected)
				Text("Shows a \"Start recording?\" nudge when another app (Zoom, Teams, Meet, FaceTime…) starts using your microphone. Never records on its own.")
					.font(.caption).foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.tabItem { Label("General", systemImage: "folder") }

		Form {
			Section("Transcription") {
				HStack {
					TextField("Default whisper model path", text: $settings.whisperModelPath)
					if modelExists {
						Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
					} else {
						Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
					}
				}
				if !modelExists {
					Text("No model at that path. Download one below.")
						.font(.caption).foregroundStyle(.orange)
				}
				TextField("Language (auto, en, uk, de, ua, …)", text: $settings.language)
				Text("Auto-detect / non-English needs a multilingual model (not the .en variant).")
					.font(.caption).foregroundStyle(.secondary)

				TextField("Vocabulary hint (optional)", text: $settings.transcriptionPrompt, axis: .vertical)
					.lineLimit(2...4)
				Text("Helps spelling of names and terms. List participant names, product/company names, and any jargon - e.g. \"Зустріч українською. Сергій, Олег, Keystone, Obsidian, whisper.\"")
					.font(.caption).foregroundStyle(.secondary)

				HStack {
					Picker("Download model", selection: $modelToDownload) {
						ForEach(ModelDownloader.available, id: \.self) { Text($0).tag($0) }
					}
					Button("Download") {
						downloader.download(model: modelToDownload) { url in
							if let url = url { settings.whisperModelPath = url.path }
						}
					}
					.disabled(downloader.isDownloading)
				}
				Text(modelInfo(modelToDownload))
					.font(.caption).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				if downloader.isDownloading {
					ProgressView(value: downloader.progress).progressViewStyle(.linear)
					Text("\(downloader.message)  \(Int(downloader.progress * 100))%")
						.font(.caption).foregroundStyle(.secondary)
				} else if !downloader.message.isEmpty {
					Text(downloader.message).font(.caption).foregroundStyle(.secondary)
				}
			}

			Section("Model per language (optional)") {
				Text("Pick a downloaded model per language - e.g. large-v3 for Ukrainian. Meetings in any language without an override use the default model above. Download models in the Transcription tab first.")
					.font(.caption).foregroundStyle(.secondary)

				ForEach(overrideLanguages, id: \.self) { lang in
					let current = settings.modelByLanguage[lang] ?? ""
					HStack {
						Text(languageName(lang)).frame(width: 90, alignment: .leading)
						Picker("", selection: Binding(
							get: { current },
							set: { v in
								var m = settings.modelByLanguage
								m[lang] = v
								settings.modelByLanguage = m
							})) {
							ForEach(modelOptions(including: current), id: \.path) { Text($0.name).tag($0.path) }
						}
						.labelsHidden()
						if modelFileExists(current) {
							Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
						} else {
							Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
						}
						Button { settings.removeModel(for: lang) } label: { Image(systemName: "trash") }
							.buttonStyle(.borderless)
					}
				}

				HStack {
					Picker("Add override for", selection: $overrideLang) {
						ForEach(unsetLanguages, id: \.code) { Text($0.name).tag($0.code) }
					}
					Button("Add") {
						settings.setModel(settings.whisperModelPath, for: overrideLang)
						overrideLang = unsetLanguages.first?.code ?? "uk"
					}
					.disabled(unsetLanguages.isEmpty)
				}
			}
		}
		.formStyle(.grouped)
		.tabItem { Label("Transcription", systemImage: "waveform") }

		Form {
			Section("Summary & action items") {
				Picker("Engine", selection: $settings.summaryEngine) {
					Text("None").tag("none")
					Text("Local (Ollama)").tag("ollama")
					Text("Claude API").tag("claude")
				}

				if settings.summaryEngine == "ollama" {
					TextField("Ollama URL", text: $settings.ollamaURL)
					HStack {
						TextField("Model (e.g. llama3.1)", text: $settings.ollamaModel)
						if !ollamaModels.isEmpty {
							Picker("", selection: $settings.ollamaModel) {
								Text("-").tag("")
								ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
							}
							.labelsHidden().frame(width: 170)
						}
						Button("Refresh", action: refreshOllama)
					}
				}

				if settings.summaryEngine == "claude" {
					SecureField("API key (sk-ant-…)", text: $settings.claudeAPIKey)
					TextField("Model", text: $settings.claudeModel)
					Text("The transcript text is sent to Anthropic when summarizing.")
						.font(.caption).foregroundStyle(.secondary)
				}

				if settings.summaryEngine != "none" {
					VStack(alignment: .leading, spacing: 4) {
						HStack {
							Text("Prompt for **\(settings.activeSummaryModel.isEmpty ? "(set a model)" : settings.activeSummaryModel)**")
								.font(.caption)
							Spacer()
							Button("Reset to default") { settings.resetCurrentPrompt() }
								.font(.caption)
								.disabled(!settings.currentPromptIsCustom)
						}
						TextEditor(text: Binding(
							get: { settings.currentPrompt() },
							set: { settings.setCurrentPrompt($0) }))
							.font(.system(.caption, design: .monospaced))
							.frame(minHeight: 300)
							.border(Color.gray.opacity(0.3))
						Text("Each model can have its own prompt. {{transcript}} is replaced.")
							.font(.caption).foregroundStyle(.secondary)
					}
				}
			}
		}
		.formStyle(.grouped)
		.tabItem { Label("Summary", systemImage: "sparkles") }

		Form {
			Section("About") {
				VStack(spacing: 10) {
					Text("AI Meeting Notes")
						.font(.headline)
					Text("Version \(Self.appVersion)")
						.font(.caption).foregroundStyle(.secondary)
					HStack(spacing: 18) {
						Link(destination: URL(string: "https://sergb.com/")!) {
							Label("Website", systemImage: "globe")
						}
						.help("sergb.com")
						Link(destination: URL(string: "https://github.com/servika/ai-meeting-notes")!) {
							Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
						}
						.help("Project on GitHub")
						Link(destination: URL(string: "https://www.linkedin.com/in/serg-bataev/")!) {
							Label("LinkedIn", systemImage: "person.crop.circle")
						}
						.help("Serg Bataev on LinkedIn")
					}
					.buttonStyle(.borderless)
					.tint(brand)
					.padding(.top, 4)
					Text("Made by Serg Bataev")
						.font(.caption2).foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
			}
		}
		.formStyle(.grouped)
		.tabItem { Label("About", systemImage: "info.circle") }
		}
		.tint(brand)
		.frame(width: 720, height: 660)
		.onAppear(perform: refreshOllama)
	}

	private func chooseVault() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Choose Vault"
		if panel.runModal() == .OK, let url = panel.url { settings.vaultPath = url.path }
	}

	private func refreshOllama() {
		guard settings.summaryEngine == "ollama" else { return }
		let url = settings.ollamaURL
		DispatchQueue.global().async {
			let models = Ollama.installedModels(url: url)
			DispatchQueue.main.async { ollamaModels = models }
		}
	}
}
