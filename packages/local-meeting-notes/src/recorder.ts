/**
 * Captures one or two audio inputs (e.g. microphone + a system-audio loopback
 * device such as BlackHole) with the Web Audio API and records to a WebM/Opus
 * blob. When both sources are present they are kept separate as a stereo split -
 * mic on the left channel, system audio on the right - so speaker separation is
 * preserved in the archive (useful for diarization). Transcription downmixes
 * this to mono later, which simply averages the two channels back together.
 */
export class MeetingRecorder {
	private ctx: AudioContext | null = null;
	private recorder: MediaRecorder | null = null;
	private chunks: Blob[] = [];
	private streams: MediaStream[] = [];

	get isRecording(): boolean {
		return this.recorder?.state === "recording";
	}

	/**
	 * Start recording. Each device id is optional; pass an empty string to skip
	 * that source. If neither resolves, falls back to the default microphone.
	 */
	async start(micDeviceId?: string, systemDeviceId?: string): Promise<void> {
		this.ctx = new AudioContext();
		const dest = this.ctx.createMediaStreamDestination();

		const getSource = async (deviceId?: string) => {
			if (!deviceId) return null;
			const stream = await navigator.mediaDevices.getUserMedia({
				audio: {
					deviceId: { exact: deviceId },
					// Keep the meeting audio clean: don't let the browser fight us.
					echoCancellation: false,
					noiseSuppression: false,
					autoGainControl: false,
				},
			});
			this.streams.push(stream);
			return this.ctx!.createMediaStreamSource(stream);
		};

		const mic = await getSource(micDeviceId);
		const system = await getSource(systemDeviceId);

		if (mic && system) {
			// Stereo split: mic → left channel, system → right channel. The merger's
			// inputs are mono, so each source is downmixed onto its single channel.
			const merger = this.ctx.createChannelMerger(2);
			mic.connect(merger, 0, 0);
			system.connect(merger, 0, 1);
			merger.connect(dest);
		} else if (mic || system) {
			// Single source - record it as-is rather than a half-silent stereo file.
			(mic ?? system)!.connect(dest);
		} else {
			// No devices selected - fall back to the default microphone.
			const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
			this.streams.push(stream);
			this.ctx.createMediaStreamSource(stream).connect(dest);
		}

		this.chunks = [];
		this.recorder = new MediaRecorder(dest.stream, { mimeType: "audio/webm" });
		this.recorder.ondataavailable = (e) => {
			if (e.data.size > 0) this.chunks.push(e.data);
		};
		// Timeslice so we accumulate chunks and don't lose everything on a crash.
		this.recorder.start(1000);
	}

	/** Stop recording and resolve with the full WebM blob. */
	stop(): Promise<Blob> {
		return new Promise((resolve) => {
			if (!this.recorder) return resolve(new Blob([], { type: "audio/webm" }));
			this.recorder.onstop = () => {
				const blob = new Blob(this.chunks, { type: "audio/webm" });
				this.cleanup();
				resolve(blob);
			};
			this.recorder.stop();
		});
	}

	private cleanup(): void {
		this.streams.forEach((s) => s.getTracks().forEach((t) => t.stop()));
		this.streams = [];
		void this.ctx?.close();
		this.ctx = null;
		this.recorder = null;
		this.chunks = [];
	}

	/** List available audio input devices (labels require granted mic permission). */
	static async listInputDevices(): Promise<MediaDeviceInfo[]> {
		const devices = await navigator.mediaDevices.enumerateDevices();
		return devices.filter((d) => d.kind === "audioinput");
	}
}