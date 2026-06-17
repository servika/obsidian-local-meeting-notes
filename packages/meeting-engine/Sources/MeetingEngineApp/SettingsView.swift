import SwiftUI
import AppKit
import MeetingEngineCore

struct SettingsView: View {
	@EnvironmentObject var settings: AppSettings
	@State private var ollamaModels: [String] = []

	var body: some View {
		Form {
			Section("Storage (Obsidian vault)") {
				HStack {
					TextField("Vault folder", text: $settings.vaultPath)
					Button("Choose…", action: chooseVault)
				}
				TextField("Meetings subfolder", text: $settings.meetingsFolder)
				Text("Notes are written to <vault>/\(settings.meetingsFolder); audio to .../recordings.")
					.font(.caption).foregroundStyle(.secondary)
			}

			Section("Transcription") {
				TextField("Whisper model path", text: $settings.whisperModelPath)
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
						Text("Prompt ({{transcript}} is replaced)").font(.caption)
						TextEditor(text: $settings.summaryPrompt)
							.font(.system(.caption, design: .monospaced))
							.frame(height: 120)
							.border(Color.gray.opacity(0.3))
					}
				}
			}
		}
		.formStyle(.grouped)
		.frame(width: 540, height: 560)
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