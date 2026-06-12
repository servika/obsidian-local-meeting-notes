/**
 * Captures one or two audio inputs (e.g. microphone + a system-audio loopback
 * device such as BlackHole), mixes them with the Web Audio API, and records the
 * mix to a single WebM/Opus blob.
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

		const addSource = async (deviceId?: string) => {
			if (!deviceId) return;
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
			this.ctx!.createMediaStreamSource(stream).connect(dest);
		};

		await addSource(micDeviceId);
		await addSource(systemDeviceId);

		if (this.streams.length === 0) {
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