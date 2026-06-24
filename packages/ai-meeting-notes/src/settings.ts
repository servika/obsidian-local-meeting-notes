import { App, PluginSettingTab, Setting, Notice } from "obsidian";
import { MeetingRecorder } from "./recorder";
import type MeetingNotesPlugin from "./main";

export interface MeetingNotesSettings {
	whisperBinaryPath: string;
	whisperModelPath: string;
	language: string;
	micDeviceId: string;
	systemDeviceId: string;
	transcriptsFolder: string;
	recordingsFolder: string;
	saveAudio: boolean;
	summaryEnabled: boolean;
	ollamaUrl: string;
	ollamaModel: string;
	summaryPrompt: string;
}

export const DEFAULT_SUMMARY_PROMPT = `You are summarizing a meeting transcript. Respond in clean Markdown with exactly these sections and nothing else:

## Summary
A concise paragraph (3-5 sentences) capturing the purpose and outcome.

## Key points
- The main topics, decisions, and conclusions, as short bullets.

## Action items
- [ ] Each task, including the owner if it was mentioned.

Transcript:
{{transcript}}`;

export const DEFAULT_SETTINGS: MeetingNotesSettings = {
	whisperBinaryPath: "whisper-cli",
	whisperModelPath: "",
	language: "auto",
	micDeviceId: "",
	systemDeviceId: "",
	transcriptsFolder: "Meetings",
	recordingsFolder: "Meetings/recordings",
	saveAudio: true,
	summaryEnabled: false,
	ollamaUrl: "http://localhost:11434",
	ollamaModel: "",
	summaryPrompt: DEFAULT_SUMMARY_PROMPT,
};

export class MeetingNotesSettingTab extends PluginSettingTab {
	plugin: MeetingNotesPlugin;

	constructor(app: App, plugin: MeetingNotesPlugin) {
		super(app, plugin);
		this.plugin = plugin;
	}

	async display(): Promise<void> {
		const { containerEl } = this;
		containerEl.empty();

		// --- Audio devices ---
		containerEl.createEl("h3", { text: "Audio sources" });

		let devices: MediaDeviceInfo[] = [];
		try {
			devices = await MeetingRecorder.listInputDevices();
		} catch {
			/* ignore - handled by the grant-access button below */
		}

		const labelled = devices.some((d) => d.label);
		if (!labelled) {
			new Setting(containerEl)
				.setName("Grant microphone access")
				.setDesc("Required once so device names show up below.")
				.addButton((b) =>
					b.setButtonText("Grant").onClick(async () => {
						try {
							const s = await navigator.mediaDevices.getUserMedia({ audio: true });
							s.getTracks().forEach((t) => t.stop());
							this.display();
						} catch (e) {
							new Notice("Access denied: " + (e as Error).message);
						}
					}),
				);
		}

		const deviceDropdown = (
			name: string,
			desc: string,
			current: string,
			onChange: (v: string) => void,
		) => {
			new Setting(containerEl)
				.setName(name)
				.setDesc(desc)
				.addDropdown((dd) => {
					dd.addOption("", "- none -");
					devices.forEach((d) =>
						dd.addOption(d.deviceId, d.label || `Input ${d.deviceId.slice(0, 6)}`),
					);
					dd.setValue(current).onChange(onChange);
				});
		};

		deviceDropdown(
			"Microphone",
			"Your voice.",
			this.plugin.settings.micDeviceId,
			async (v) => {
				this.plugin.settings.micDeviceId = v;
				await this.plugin.saveSettings();
			},
		);

		deviceDropdown(
			"System audio (loopback)",
			"The other participants. Select your loopback (virtual audio) device.",
			this.plugin.settings.systemDeviceId,
			async (v) => {
				this.plugin.settings.systemDeviceId = v;
				await this.plugin.saveSettings();
			},
		);

		// --- whisper.cpp ---
		containerEl.createEl("h3", { text: "Transcription (whisper.cpp)" });

		new Setting(containerEl)
			.setName("whisper-cli binary")
			.setDesc('Path or command. Default "whisper-cli" works if installed via `brew install whisper-cpp`.')
			.addText((t) =>
				t
					.setValue(this.plugin.settings.whisperBinaryPath)
					.onChange(async (v) => {
						this.plugin.settings.whisperBinaryPath = v.trim();
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Model path")
			.setDesc("Absolute path to a ggml model, e.g. ~/models/ggml-base.en.bin")
			.addText((t) =>
				t
					.setValue(this.plugin.settings.whisperModelPath)
					.onChange(async (v) => {
						this.plugin.settings.whisperModelPath = v.trim();
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Language")
			.setDesc('Language code (e.g. "en") or "auto".')
			.addText((t) =>
				t.setValue(this.plugin.settings.language).onChange(async (v) => {
					this.plugin.settings.language = v.trim() || "auto";
					await this.plugin.saveSettings();
				}),
			);

		// --- Output ---
		containerEl.createEl("h3", { text: "Output" });

		new Setting(containerEl)
			.setName("Transcripts folder")
			.setDesc("Vault folder where transcript notes are created.")
			.addText((t) =>
				t.setValue(this.plugin.settings.transcriptsFolder).onChange(async (v) => {
					this.plugin.settings.transcriptsFolder = v.trim();
					await this.plugin.saveSettings();
				}),
			);

		new Setting(containerEl)
			.setName("Save audio file")
			.setDesc("Keep the recorded audio in the vault alongside the transcript.")
			.addToggle((tg) =>
				tg.setValue(this.plugin.settings.saveAudio).onChange(async (v) => {
					this.plugin.settings.saveAudio = v;
					await this.plugin.saveSettings();
				}),
			);

		new Setting(containerEl)
			.setName("Recordings folder")
			.setDesc("Vault folder for saved audio (when enabled).")
			.addText((t) =>
				t.setValue(this.plugin.settings.recordingsFolder).onChange(async (v) => {
					this.plugin.settings.recordingsFolder = v.trim();
					await this.plugin.saveSettings();
				}),
			);

		// --- AI summary (local LLM via Ollama) ---
		containerEl.createEl("h3", { text: "AI summary (optional)" });
		containerEl.createEl("p", {
			text: "Off by default. When enabled, the transcript is sent to a local Ollama instance to generate a summary and action items. This is a localhost request - nothing leaves your machine.",
			cls: "setting-item-description",
		});

		new Setting(containerEl)
			.setName("Generate summary")
			.setDesc("Run each transcript through a local LLM after transcription.")
			.addToggle((tg) =>
				tg.setValue(this.plugin.settings.summaryEnabled).onChange(async (v) => {
					this.plugin.settings.summaryEnabled = v;
					await this.plugin.saveSettings();
				}),
			);

		new Setting(containerEl)
			.setName("Ollama URL")
			.setDesc("Base URL of your local Ollama server.")
			.addText((t) =>
				t.setValue(this.plugin.settings.ollamaUrl).onChange(async (v) => {
					this.plugin.settings.ollamaUrl = v.trim() || "http://localhost:11434";
					await this.plugin.saveSettings();
				}),
			);

		new Setting(containerEl)
			.setName("Ollama model")
			.setDesc('Model name as shown by `ollama list`, e.g. "llama3.1" or "gpt-oss:20b".')
			.addText((t) =>
				t
					.setPlaceholder("llama3.1")
					.setValue(this.plugin.settings.ollamaModel)
					.onChange(async (v) => {
						this.plugin.settings.ollamaModel = v.trim();
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Summary prompt")
			.setDesc("Uses {{transcript}} as a placeholder for the transcript text.")
			.addTextArea((ta) => {
				ta.setValue(this.plugin.settings.summaryPrompt).onChange(async (v) => {
					this.plugin.settings.summaryPrompt = v;
					await this.plugin.saveSettings();
				});
				ta.inputEl.rows = 10;
				ta.inputEl.style.width = "100%";
			});
	}
}