/**
 * Decode an arbitrary audio blob and re-render it to the format whisper.cpp
 * expects: 16 kHz, mono, 16-bit PCM WAV. Done entirely in the browser via
 * OfflineAudioContext so we don't need ffmpeg on the user's machine. A stereo
 * recording (mic-left / system-right) is downmixed to mono here automatically -
 * the single mono channel is the average of both, i.e. the full meeting.
 */
export async function blobToWav16kMono(blob: Blob): Promise<ArrayBuffer> {
	const arrayBuffer = await blob.arrayBuffer();

	const decodeCtx = new AudioContext();
	const decoded = await decodeCtx.decodeAudioData(arrayBuffer);
	void decodeCtx.close();

	const targetRate = 16000;
	const frames = Math.ceil(decoded.duration * targetRate);
	const offline = new OfflineAudioContext(1, frames, targetRate);
	const source = offline.createBufferSource();
	source.buffer = decoded;
	source.connect(offline.destination);
	source.start();
	const rendered = await offline.startRendering();

	return encodeWav(rendered.getChannelData(0), targetRate);
}

function encodeWav(samples: Float32Array, sampleRate: number): ArrayBuffer {
	const buffer = new ArrayBuffer(44 + samples.length * 2);
	const view = new DataView(buffer);

	const writeString = (offset: number, str: string) => {
		for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
	};

	writeString(0, "RIFF");
	view.setUint32(4, 36 + samples.length * 2, true);
	writeString(8, "WAVE");
	writeString(12, "fmt ");
	view.setUint32(16, 16, true); // PCM chunk size
	view.setUint16(20, 1, true); // audio format = PCM
	view.setUint16(22, 1, true); // channels = mono
	view.setUint32(24, sampleRate, true);
	view.setUint32(28, sampleRate * 2, true); // byte rate
	view.setUint16(32, 2, true); // block align
	view.setUint16(34, 16, true); // bits per sample
	writeString(36, "data");
	view.setUint32(40, samples.length * 2, true);

	let offset = 44;
	for (let i = 0; i < samples.length; i++) {
		const s = Math.max(-1, Math.min(1, samples[i]));
		view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
		offset += 2;
	}

	return buffer;
}