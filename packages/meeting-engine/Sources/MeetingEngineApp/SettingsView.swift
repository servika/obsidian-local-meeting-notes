import SwiftUI
import AppKit
import MeetingEngineCore

struct SettingsView: View {
	@EnvironmentObject var settings: AppSettings
	@EnvironmentObject var updates: UpdateChecker
	@StateObject private var downloader = ModelDownloader()
	@State private var ollamaModels: [String] = []
	@State private var ollamaState: OllamaState?   // nil = checking
	@State private var pulling = false
	@State private var pullProgress: Double = 0
	@State private var pullStatus = ""
	@State private var ollamaModelToPull = ""
	@State private var modelToDownload = "base"
	@State private var overrideLang = "uk"
	@State private var presetMessage = ""

	static var appVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
	}

	private var modelExists: Bool {
		modelFileExists(settings.whisperModelPath)
	}

	// MARK: hardware-based recommendations

	/// Installed physical memory, rounded to GB.
	private var systemRAMGB: Int {
		Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
	}

	/// Recommended whisper model for this Mac's RAM (multilingual; balances
	/// accuracy vs. memory/speed).
	private var recommendedWhisperModel: String {
		let gb = systemRAMGB
		if gb >= 24 { return "large-v3" }
		if gb >= 12 { return "large-v3-turbo" }
		return "small"
	}

	/// Recommended local (Ollama) summary model for this Mac's RAM.
	private var recommendedOllamaModel: String {
		let gb = systemRAMGB
		if gb >= 48 { return "qwen2.5:32b" }
		if gb >= 24 { return "qwen2.5:14b" }
		if gb >= 12 { return "qwen2.5:7b" }
		return "qwen2.5:3b"
	}

	/// Curated local summary models to offer in the download picker, recommended
	/// size for this Mac first.
	private var ollamaSuggestedModels: [String] {
		var list = ["qwen2.5:3b", "qwen2.5:7b", "qwen2.5:14b", "qwen2.5:32b", "llama3.1:8b", "gpt-oss:20b"]
		list.removeAll { $0 == recommendedOllamaModel }
		return [recommendedOllamaModel] + list
	}

	/// Whether the diarization binary + models are installed (drives the toggle).
	private var speakerRecognitionAvailable: Bool { Diarizer.isAvailable() }
	private var speakerRecognitionUnavailableReason: String? { Diarizer.unavailableReason() }

	/// Per-flag dependency checks - a flag may need extra binaries/models before
	/// it can be turned on.
	private func isFlagAvailable(_ flag: FeatureFlag) -> Bool {
		flagUnavailableReason(flag) == nil
	}

	private func flagUnavailableReason(_ flag: FeatureFlag) -> String? {
		switch flag {
		case .speakerRecognition: return speakerRecognitionUnavailableReason
		}
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
			Section("Storage") {
				HStack {
					TextField("Notes folder", text: $settings.vaultPath)
					Button("Choose…", action: chooseVault)
				}
				TextField("Meetings subfolder", text: $settings.meetingsFolder)
				Text("Meetings are saved as Markdown in this folder. Any folder works.")
					.font(.caption).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Section("Recording") {
				Toggle("Suggest recording when a meeting is detected", isOn: $settings.suggestOnMeetingDetected)
				Text("Shows a \"Start recording?\" nudge when another app (Zoom, Teams, Meet, FaceTime…) starts using your microphone. Never records on its own.")
					.font(.caption).foregroundStyle(.secondary)
			}

			Section("Experimental features") {
				Toggle("Enable experimental features", isOn: $settings.experimentalMode)
				Text("Turns on new, in-development R&D features. These are rough around the edges and may change or be removed - off by default so the regular experience is unaffected.")
					.font(.caption).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				ForEach(FeatureFlag.allCases) { flag in
					Toggle(flag.title, isOn: settings.flagBinding(flag))
						.disabled(!settings.experimentalMode || !isFlagAvailable(flag))
					Text(flag.details)
						.font(.caption).foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
					if settings.experimentalMode, let reason = flagUnavailableReason(flag) {
						stageNote("Unavailable: \(reason).")
					}
				}
			}
		}
		.formStyle(.grouped)
		.tabItem { Label("General", systemImage: "folder") }

		Form {
			Section {
				Toggle("Transcribe meetings", isOn: $settings.transcribeMeetings)
					.disabled(!settings.transcriptionAvailable)
				if settings.transcribeMeetings, let reason = settings.transcriptionUnavailableReason {
					stageNote(reason)
				}
				Text("When on, each recording is transcribed after it stops. Audio is always saved either way.")
					.font(.caption).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Section("Quick setup") {
				HStack {
					Button {
						applyUkrainianPreset()
					} label: {
						Label("Best quality for Ukrainian", systemImage: "star.fill")
					}
					.disabled(downloader.isDownloading)
					if !presetMessage.isEmpty {
						Text(presetMessage).font(.caption).foregroundStyle(.secondary)
					}
				}
				Text("Sets the meeting language to Ukrainian and uses the large-v3 model for it (downloads it first if needed). Best accuracy; slower than base.")
					.font(.caption).foregroundStyle(.secondary)
			}

			Section("Transcription") {
				HStack {
					Picker("Default model", selection: $settings.whisperModelPath) {
						ForEach(modelOptions(including: settings.whisperModelPath), id: \.path) {
							Text($0.name).tag($0.path)
						}
					}
					if modelExists {
						Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
					} else {
						Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
					}
				}
				if !modelExists {
					Text("No model downloaded yet. Download one below.")
						.font(.caption).foregroundStyle(.orange)
				}
				TextField("Language (auto, en, uk, de, ua, …)", text: $settings.language)
				Text("Auto-detect / non-English needs a multilingual model (not the .en variant).")
					.font(.caption).foregroundStyle(.secondary)

				TextField("Vocabulary hint (optional)", text: $settings.transcriptionPrompt, axis: .vertical)
					.lineLimit(2...4)
				Text("Helps spelling of names and terms. List participant names, product/company names, and any jargon - e.g. \"Зустріч українською. Сергій, Олег, Keystone, Acme, whisper.\"")
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
				Label("Recommended for your \(systemRAMGB) GB Mac: \(recommendedWhisperModel)", systemImage: "sparkles")
					.font(.caption).foregroundStyle(brand)
				if downloader.isDownloading {
					ProgressView(value: downloader.progress).progressViewStyle(.linear)
					Text("\(downloader.message)  \(Int(downloader.progress * 100))%")
						.font(.caption).foregroundStyle(.secondary)
				} else if !downloader.message.isEmpty {
					Text(downloader.message).font(.caption).foregroundStyle(.secondary)
				}
			}

				if settings.isEnabled(.speakerRecognition), speakerRecognitionAvailable {
					Section("Speaker recognition") {
						Picker("Speakers on the call (their side)", selection: $settings.speakerCount) {
							Text("Auto-detect").tag(0)
							ForEach(2...8, id: \.self) { Text("\($0)").tag($0) }
						}
						Text("Auto-detect is unreliable on real meeting audio - setting the exact number of remote speakers gives much better results. This is the default for new recordings; each meeting also keeps its own count (editable before re-generating). Turn the feature on/off under General → Experimental features.")
							.font(.caption).foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
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
				Toggle("Generate summary & action items", isOn: $settings.summarizeMeetings)
					.disabled(!settings.transcribeMeetings || !settings.summaryAvailable)
				if !settings.transcribeMeetings {
					stageNote("Turn on transcription first (Transcription tab) - the summary is generated from the transcript.")
				} else if settings.summarizeMeetings, let reason = settings.summaryUnavailableReason {
					stageNote(reason)
				}
				Text("When on, each transcript is summarized into a short summary, topics, and action items.")
					.font(.caption).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Picker("Engine", selection: $settings.summaryEngine) {
					Text("Local (Ollama)").tag("ollama")
					Text("Claude API").tag("claude")
				}

				if settings.summaryEngine == "ollama" {
					TextField("Ollama URL", text: $settings.ollamaURL)

					switch ollamaState {
					case .running:
						Label("Ollama is running", systemImage: "checkmark.circle.fill")
							.font(.caption).foregroundStyle(.green)
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
						if pulling {
							ProgressView(value: pullProgress >= 0 ? pullProgress : nil) {
								Text(pullStatus).font(.caption)
							}
							.progressViewStyle(.linear)
						} else {
							HStack {
								Picker("Download model", selection: $ollamaModelToPull) {
									ForEach(ollamaSuggestedModels, id: \.self) { Text($0).tag($0) }
								}
								Button("Download") { pullOllamaModel(ollamaModelToPull) }
									.disabled(ollamaModelToPull.isEmpty)
							}
							Label("Recommended for your \(systemRAMGB) GB Mac: \(recommendedOllamaModel)", systemImage: "sparkles")
								.font(.caption).foregroundStyle(brand)
							if !pullStatus.isEmpty, pullStatus.hasPrefix("Download failed") {
								Text(pullStatus).font(.caption).foregroundStyle(.orange)
							}
						}
						if systemRAMGB < 12 {
							Text("On low-RAM Macs, Claude (above) gives the best quality without local memory limits.")
								.font(.caption).foregroundStyle(.secondary)
						}

					case .installedNotRunning:
						Label("Ollama is installed but not running", systemImage: "exclamationmark.triangle.fill")
							.font(.caption).foregroundStyle(.orange)
						HStack {
							Button("Open Ollama", action: openOllamaApp)
							Button("Re-check", action: refreshOllama)
						}
						Text("Start the Ollama app (it runs in the menu bar), then click Re-check. Or use the Claude engine above.")
							.font(.caption).foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)

					case .notInstalled:
						Label("Ollama isn't installed", systemImage: "exclamationmark.triangle.fill")
							.font(.caption).foregroundStyle(.orange)
						HStack {
							Link(destination: URL(string: "https://ollama.com/download")!) {
								Label("Download Ollama", systemImage: "arrow.down.circle")
							}
							.buttonStyle(.borderedProminent).tint(brand)
							Button("Re-check", action: refreshOllama)
						}
						Text("Ollama is a free local model runner. Install it, then click Re-check - or use the Claude engine above (no install, uses your API key).")
							.font(.caption).foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)

					case nil:
						HStack(spacing: 6) {
							ProgressView().controlSize(.small)
							Text("Checking Ollama…").font(.caption).foregroundStyle(.secondary)
						}
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

					if updates.updateAvailable, let v = updates.latestVersion, let url = updates.releaseURL {
						Link(destination: url) {
							Label("Update available: \(v) - Download", systemImage: "arrow.down.circle.fill")
						}
						.buttonStyle(.borderedProminent).controlSize(.small).tint(brand)
					} else {
						HStack(spacing: 8) {
							Button(updates.checking ? "Checking…" : "Check for updates") { updates.check() }
								.controlSize(.small).disabled(updates.checking)
							if !updates.status.isEmpty {
								Text(updates.status).font(.caption).foregroundStyle(.secondary)
							}
						}
					}

					HStack(spacing: 18) {
						Link(destination: URL(string: "https://github.com/servika/ai-meeting-notes")!) {
							Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
						}
						.help("Project on GitHub")
						Link(destination: URL(string: "https://github.com/servika/ai-meeting-notes/blob/main/THIRD-PARTY-NOTICES.md")!) {
							Label("Credits & licenses", systemImage: "doc.text")
						}
						.help("Open-source components this app is built on")
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
		.onChange(of: settings.summaryEngine) { refreshOllama() }
	}

	/// An orange "unavailable / dependency" note shown under a stage toggle.
	private func stageNote(_ text: String) -> some View {
		Label(text, systemImage: "exclamationmark.triangle.fill")
			.font(.caption).foregroundStyle(.orange)
			.fixedSize(horizontal: false, vertical: true)
	}

	private func chooseVault() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Choose Folder"
		if panel.runModal() == .OK, let url = panel.url { settings.vaultPath = url.path }
	}

	/// One-click "best quality for Ukrainian": language = uk and large-v3 pinned
	/// to Ukrainian (downloaded first if it isn't present).
	private func applyUkrainianPreset() {
		settings.language = "uk"
		let path = ("~/models/ggml-large-v3.bin" as NSString).expandingTildeInPath
		if FileManager.default.fileExists(atPath: path) {
			settings.setModel(path, for: "uk")
			presetMessage = "Ukrainian → large-v3 ✓"
			return
		}
		presetMessage = "Downloading large-v3…"
		downloader.download(model: "large-v3") { url in
			if let url = url {
				settings.setModel(url.path, for: "uk")
				presetMessage = "Ukrainian → large-v3 ✓"
			} else {
				presetMessage = "Download failed - try again."
			}
		}
	}

	private func refreshOllama() {
		guard settings.summaryEngine == "ollama" else { return }
		if ollamaModelToPull.isEmpty { ollamaModelToPull = recommendedOllamaModel }
		ollamaState = nil // checking…
		let url = settings.ollamaURL
		DispatchQueue.global().async {
			let state = Ollama.status(url: url)
			let models: [String] = { if case let .running(m) = state { return m } else { return [] } }()
			DispatchQueue.main.async { ollamaState = state; ollamaModels = models }
		}
	}

	/// Download an Ollama model in-app (no terminal) via the pull API, with progress.
	private func pullOllamaModel(_ model: String) {
		guard !pulling, !model.isEmpty else { return }
		pulling = true; pullProgress = 0; pullStatus = "Starting download…"
		let url = settings.ollamaURL
		Task {
			do {
				try await Ollama.pull(model: model, url: url) { p, s in
					Task { @MainActor in pullProgress = p; pullStatus = s }
				}
				await MainActor.run { settings.ollamaModel = model; pulling = false; refreshOllama() }
			} catch {
				await MainActor.run { pulling = false; pullStatus = "Download failed: \(error)" }
			}
		}
	}

	/// Launch the installed Ollama app, then re-check shortly after.
	private func openOllamaApp() {
		let paths = ["/Applications/Ollama.app",
			(NSHomeDirectory() as NSString).appendingPathComponent("Applications/Ollama.app")]
		if let p = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
			NSWorkspace.shared.open(URL(fileURLWithPath: p))
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: refreshOllama)
	}
}
