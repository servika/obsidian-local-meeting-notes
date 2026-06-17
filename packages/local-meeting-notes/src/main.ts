import { Notice, Plugin, TFile, normalizePath } from "obsidian";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { MeetingRecorder } from "./recorder";
import { blobToWav16kMono } from "./wav";
import { transcribe } from "./transcription";
import {
	DEFAULT_SETTINGS,
	MeetingNotesSettings,
	MeetingNotesSettingTab,
} from "./settings";

export default class MeetingNotesPlugin extends Plugin {
	settings!: MeetingNotesSettings;
	recorder = new MeetingRecorder();
	private statusBar!: HTMLElement;

	async onload(): Promise<void> {
		await this.loadSettings();

		this.statusBar = this.addStatusBarItem();
		this.updateStatus();

		this.addRibbonIcon("mic", "Start / stop meeting recording", () => this.toggle());

		this.addCommand({
			id: "toggle-recording",
			name: "Toggle meeting recording",
			callback: () => this.toggle(),
		});
		this.addCommand({
			id: "start-recording",
			name: "Start meeting recording",
			checkCallback: (checking) => {
				if (this.recorder.isRecording) return false;
				if (!checking) void this.start();
				return true;
			},
		});
		this.addCommand({
			id: "stop-recording",
			name: "Stop recording & transcribe",
			checkCallback: (checking) => {
				if (!this.recorder.isRecording) return false;
				if (!checking) void this.stop();
				return true;
			},
		});

		this.addSettingTab(new MeetingNotesSettingTab(this.app, this));
	}

	async onunload(): Promise<void> {
		if (this.recorder.isRecording) await this.recorder.stop();
	}

	private async toggle(): Promise<void> {
		if (this.recorder.isRecording) await this.stop();
		else await this.start();
	}

	private async start(): Promise<void> {
		try {
			await this.recorder.start(
				this.settings.micDeviceId,
				this.settings.systemDeviceId,
			);
			this.updateStatus();
			new Notice("🔴 Recording meeting…");
		} catch (e) {
			new Notice("Failed to start recording: " + (e as Error).message);
		}
	}

	private async stop(): Promise<void> {
		if (!this.recorder.isRecording) return;
		const blob = await this.recorder.stop();
		this.updateStatus();
		new Notice("Transcribing… this can take a moment.");
		try {
			await this.process(blob);
		} catch (e) {
			new Notice("Transcription failed: " + (e as Error).message);
			console.error("[meeting-notes]", e);
		}
	}

	/** Convert → save → transcribe → write note. */
	private async process(blob: Blob): Promise<void> {
		const stamp = window.moment().format("YYYY-MM-DD HH-mm-ss");

		if (this.settings.saveAudio) {
			await this.saveAudio(blob, stamp);
		}

		const wav = await blobToWav16kMono(blob);
		const tmpWav = path.join(os.tmpdir(), `meeting-${Date.now()}.wav`);
		fs.writeFileSync(tmpWav, Buffer.from(wav));

		let transcript: string;
		try {
			transcript = await transcribe(tmpWav, {
				binaryPath: this.settings.whisperBinaryPath,
				modelPath: this.settings.whisperModelPath,
				language: this.settings.language,
			});
		} finally {
			fs.rmSync(tmpWav, { force: true });
		}

		await this.writeNote(stamp, transcript);
		new Notice("✅ Transcript ready");
	}

	private async saveAudio(blob: Blob, stamp: string): Promise<void> {
		await this.ensureFolder(this.settings.recordingsFolder);
		const audioPath = normalizePath(
			`${this.settings.recordingsFolder}/Meeting ${stamp}.webm`,
		);
		await this.app.vault.createBinary(audioPath, await blob.arrayBuffer());
	}

	private async writeNote(stamp: string, transcript: string): Promise<void> {
		await this.ensureFolder(this.settings.transcriptsFolder);
		const notePath = normalizePath(
			`${this.settings.transcriptsFolder}/Meeting ${stamp}.md`,
		);
		const body =
			`---\ntype: meeting\ndate: ${stamp}\n---\n\n` +
			`# Meeting - ${stamp}\n\n## Transcript\n\n${transcript || "_(empty)_"}\n`;
		const file = await this.app.vault.create(notePath, body);
		if (file instanceof TFile) {
			await this.app.workspace.getLeaf(true).openFile(file);
		}
	}

	private async ensureFolder(folder: string): Promise<void> {
		const normalized = normalizePath(folder);
		if (!normalized) return;
		if (!this.app.vault.getAbstractFileByPath(normalized)) {
			await this.app.vault.createFolder(normalized).catch(() => {});
		}
	}

	private updateStatus(): void {
		this.statusBar.setText(this.recorder.isRecording ? "🔴 Recording" : "");
	}

	async loadSettings(): Promise<void> {
		this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
	}

	async saveSettings(): Promise<void> {
		await this.saveData(this.settings);
	}
}