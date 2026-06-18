import SwiftUI
import AppKit
import MeetingEngineCore

struct SettingsView: View {
	@EnvironmentObject var settings: AppSettings
	@StateObject private var downloader = ModelDownloader()
	@State private var ollamaModels: [String] = []
	@State private var modelToDownload = "base"

	static var appVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
	}

	private var modelExists: Bool {
		let p = (settings.whisperModelPath as NSString).expandingTildeInPath
		return !p.isEmpty && FileManager.default.fileExists(atPath: p)
	}

	var body: some View {
		Form {
			Section("Storage (Obsidian vault)") {
				HStack {
					TextField("Vault folder", text: $settings.vaultPath)
					Button("Choose…", action: chooseVault)
				}
				TextField("Meetings subfolder", text: $settings.meetingsFolder)
			}

			Section("Transcription") {
				HStack {
					TextField("Whisper model path", text: $settings.whisperModelPath)
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
				if downloader.isDownloading {
					ProgressView(value: downloader.progress).progressViewStyle(.linear)
					Text("\(downloader.message)  \(Int(downloader.progress * 100))%")
						.font(.caption).foregroundStyle(.secondary)
				} else if !downloader.message.isEmpty {
					Text(downloader.message).font(.caption).foregroundStyle(.secondary)
				}
			}

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
							.frame(height: 150)
							.border(Color.gray.opacity(0.3))
						Text("Each model can have its own prompt. {{transcript}} is replaced.")
							.font(.caption).foregroundStyle(.secondary)
					}
				}
			}

			Section {
				HStack {
					Spacer()
					Text("AI Meeting Notes \(Self.appVersion)")
						.font(.caption).foregroundStyle(.secondary)
					Spacer()
				}
			}
		}
		.formStyle(.grouped)
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
