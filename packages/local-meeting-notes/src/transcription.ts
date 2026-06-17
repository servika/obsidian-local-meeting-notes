import { spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export interface TranscribeOptions {
	binaryPath: string;
	modelPath: string;
	language: string;
	threads?: number;
}

/** Expand a leading ~ to the user's home directory (fs/spawn don't do this). */
function expandHome(p: string): string {
	if (p === "~") return os.homedir();
	if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
	return p;
}

/**
 * Run whisper.cpp over a 16 kHz mono WAV file and return the transcript text.
 * Uses the CLI's `-otxt` output so we don't have to parse stdout.
 */
export async function transcribe(wavPath: string, opts: TranscribeOptions): Promise<string> {
	const modelPath = expandHome(opts.modelPath);
	if (!modelPath || !fs.existsSync(modelPath)) {
		throw new Error(`whisper model not found at "${opts.modelPath}" - set it in plugin settings`);
	}

	const outBase = wavPath.replace(/\.wav$/, "");
	const args = [
		"-m", modelPath,
		"-f", wavPath,
		"-l", opts.language || "auto",
		"-otxt",
		"-of", outBase,
		"-np", // no progress prints
	];
	if (opts.threads && opts.threads > 0) args.push("-t", String(opts.threads));

	await runProcess(expandHome(opts.binaryPath), args);

	const txtPath = `${outBase}.txt`;
	const text = fs.readFileSync(txtPath, "utf8");
	fs.unlinkSync(txtPath);
	return text.trim();
}

function runProcess(cmd: string, args: string[]): Promise<void> {
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args);
		let stderr = "";
		child.stderr.on("data", (d) => (stderr += d.toString()));
		child.on("error", (err) =>
			reject(new Error(`failed to launch "${cmd}": ${err.message}`)),
		);
		child.on("close", (code) => {
			if (code === 0) resolve();
			else reject(new Error(`whisper exited with code ${code}: ${stderr.slice(-400)}`));
		});
	});
}