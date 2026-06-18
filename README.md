# AI Meeting Notes

> Record meetings - **your microphone + the other participants' audio** - and transcribe them **100% locally** with [whisper.cpp](https://github.com/ggerganov/whisper.cpp). No cloud, no API keys, no companion server. Your audio never leaves your machine.

![status: alpha](https://img.shields.io/badge/status-alpha-orange) ![platform: desktop](https://img.shields.io/badge/platform-desktop-blue) ![license: MIT](https://img.shields.io/badge/license-MIT-green)

🌐 **Website:** https://servika.github.io/ai-meeting-notes/

This repo offers **two ways** to capture, transcribe, and summarize meetings entirely on your Mac:

- 🖥️ **macOS app** (`packages/meeting-engine`) - **recommended**. Zero-setup capture of system audio + your mic (no BlackHole), a meetings library, AI summaries, and a tabbed review UI.
- 🧩 **Obsidian plugin** (`packages/ai-meeting-notes`) - records and transcribes inside your vault (uses a BlackHole loopback for system audio).

Both are local-first: transcription runs on your machine via [whisper.cpp](https://github.com/ggerganov/whisper.cpp); summaries can use a local [Ollama](https://ollama.com) model (or, optionally, the Claude API).

---

## 🖥️ macOS app (recommended)

Zero-setup system-audio + microphone capture via Core Audio process taps (no BlackHole), local transcription with **automatic language detection**, **"You vs. Them" diarization**, AI summaries (short summary, summary, topics discussed, action items), and a **meetings library** that writes notes into your Obsidian vault. Record/stop, re-generate, rename, delete, and copy-as-Markdown from the UI.

```bash
cd packages/meeting-engine
./scripts/build-app.sh
open ".build/AI Meeting Notes.app"
```

Full setup and details: **[packages/meeting-engine/README.md](packages/meeting-engine/README.md)** · live site: **https://servika.github.io/ai-meeting-notes/**

---

# Obsidian plugin

The rest of this README covers the Obsidian plugin.

## Why this plugin

- 🔒 **Fully local & private.** Transcription runs on your machine via `whisper.cpp`. Nothing is uploaded.
- 🎙️ **Captures the whole meeting.** Mixes your mic with the call's system audio (the other participants), not just you.
- 🪶 **Zero infrastructure.** No companion server, no bundled multi-hundred-MB model, no `ffmpeg` - audio is resampled to whisper's format in-browser via `OfflineAudioContext`.
- 📝 **Straight into your vault.** A timestamped Markdown note with frontmatter and the transcript, with the audio optionally saved alongside.
- 🤖 **Optional AI summary & action items.** Opt-in summarization via a local [Ollama](https://ollama.com) model - still 100% on your machine, off by default.

> **Desktop only.** Capturing system audio and running a local binary require Obsidian's desktop app.

---

## How it works

```
 Mic ─┐
      ├─► Web Audio mixer ─► MediaRecorder (WebM/Opus) ─► OfflineAudioContext
 Sys ─┘   (BlackHole)                                    (resample → 16 kHz mono WAV)
                                                                    │
                                                       whisper.cpp (whisper-cli)
                                                                    │
                                                         transcript ─► Markdown note
```

Transcription is **batch**: you record the whole meeting, then transcribe when you stop. This is simpler and more accurate than streaming (whisper sees the full context). Near-live chunked transcription is on the [roadmap](#roadmap).

---

## Prerequisites (macOS)

This plugin orchestrates two external pieces you install once. It does **not** bundle them.

### 1. A loopback device for system audio

System audio capture on macOS requires a virtual audio device. [BlackHole](https://github.com/ExistentialAudio/BlackHole) is free and open source:

```bash
brew install blackhole-2ch
```

Then, so you can still **hear** the meeting while it's captured, open **Audio MIDI Setup** and create a **Multi-Output Device** containing both your speakers/headphones **and** BlackHole, and select it as your system output.

> If you only want to record your own microphone, you can skip BlackHole entirely.

### 2. whisper.cpp + a model

```bash
brew install whisper-cpp

# Download a model (base.en is a good starting point, ~141 MB)
mkdir -p ~/models
curl -L -o ~/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

Larger models (`small`, `medium`, `large-v3`) are more accurate but slower. Browse them at the [whisper.cpp model list](https://huggingface.co/ggerganov/whisper.cpp/tree/main).

> **Linux/Windows:** the architecture is portable, but the loopback setup differs (e.g. PulseAudio/PipeWire monitor sources on Linux). Community help wanted - see [Contributing](#contributing).

---

## Installation

### Via BRAT (recommended while in alpha)

1. Install the [BRAT](https://github.com/TfTHacker/obsidian42-brat) community plugin.
2. BRAT → **Add Beta Plugin** → `servika/ai-meeting-notes`.
3. Enable **AI Meeting Notes** in **Settings → Community plugins**.

### Manual

1. Download `main.js`, `manifest.json`, and `versions.json` from the [latest release](https://github.com/servika/ai-meeting-notes/releases).
2. Copy them into `<your-vault>/.obsidian/plugins/ai-meeting-notes/`.
3. Reload Obsidian and enable the plugin under **Settings → Community plugins**.

---

## Setup in Obsidian

Open **Settings → AI Meeting Notes**:

1. Click **Grant** to allow microphone access (needed once so device names appear).
2. Choose your **Microphone** and your **System audio (loopback)** device (e.g. *BlackHole 2ch*).
3. Set **Model path** to your model file, e.g. `~/models/ggml-base.en.bin`.
4. The **whisper-cli binary** defaults to `whisper-cli` (works if installed via Homebrew); override with a full path if needed.

---

## Usage

> 📖 **New here? Read the [step-by-step usage guide](docs/USAGE.md)** - it walks through the macOS audio routing (the part people get stuck on) from zero to your first transcript.

- Click the **microphone ribbon icon**, or run a command from the palette:
  - **Start meeting recording**
  - **Stop recording & transcribe**
  - **Toggle meeting recording**
- A 🔴 indicator appears in the status bar while recording.
- On stop, the audio is resampled, transcribed, and a note is created in your **Transcripts folder** (default `Meetings/`). If **Save audio file** is on, the `.webm` is kept in the **Recordings folder**.

---

## Settings reference

| Setting | Default | Description |
|---|---|---|
| Microphone | - | Input device for your voice. |
| System audio (loopback) | - | The other participants (e.g. BlackHole). Leave empty for mic-only. |
| whisper-cli binary | `whisper-cli` | Command or absolute path to the whisper.cpp CLI. |
| Model path | - | Absolute path (or `~/…`) to a `ggml-*.bin` model. |
| Language | `auto` | Language code (e.g. `en`) or `auto`. |
| Transcripts folder | `Meetings` | Vault folder for transcript notes. |
| Save audio file | `true` | Keep the recorded audio in the vault. |
| Recordings folder | `Meetings/recordings` | Where saved audio goes. |
| Generate summary | `false` | Run each transcript through a local LLM for a summary + action items. |
| Ollama URL | `http://localhost:11434` | Base URL of your local Ollama server. |
| Ollama model | - | Model name from `ollama list` (e.g. `llama3.1`, `gpt-oss:20b`). |
| Summary prompt | *(built-in)* | Prompt template; `{{transcript}}` is replaced with the text. |

---

## Troubleshooting

- **"whisper model not found"** - set the **Model path** to the absolute path of your `.bin` file. `~` is expanded.
- **Device names are blank** - click **Grant** in settings to authorize microphone access, then reopen settings.
- **Only my voice is transcribed** - your system-audio device isn't selected, or the call's audio isn't routed through BlackHole. Check your macOS output device / Multi-Output Device.
- **Transcription is slow** - use a smaller model (`base.en`/`small.en`), or pass more threads. Apple Silicon transcribes `base` far faster than realtime.
- **Plugin doesn't appear after install** - reload Obsidian (Cmd-R) or toggle Community plugins off/on.

---

## Development

The plugin lives in `packages/ai-meeting-notes/` (monorepo layout).

```bash
git clone https://github.com/servika/ai-meeting-notes
cd ai-meeting-notes/packages/ai-meeting-notes
npm install
npm run dev     # watch build → main.js
npm run build   # type-check + production build
```

For live iteration, symlink the **package** directory into a test vault:

```bash
# from packages/ai-meeting-notes
ln -s "$(pwd)" "<your-vault>/.obsidian/plugins/ai-meeting-notes"
```

Source layout (within `packages/ai-meeting-notes/`):

| File | Role |
|---|---|
| `src/main.ts` | Plugin entry - commands, ribbon, orchestration |
| `src/recorder.ts` | Captures + mixes mic and system audio via Web Audio |
| `src/wav.ts` | Resamples to 16 kHz mono WAV (no ffmpeg) |
| `src/transcription.ts` | Spawns `whisper-cli`, reads the transcript |
| `src/settings.ts` | Settings tab |

---

## Roadmap

- [x] AI summary & action items from the transcript (local LLM via Ollama)
- [ ] Near-live transcription (rolling chunks)
- [ ] Speaker diarization
- [ ] Linux / Windows loopback setup guides

---

## Privacy

By default this plugin makes **no network requests**. Audio is recorded, resampled, and transcribed entirely on your device via the `whisper.cpp` binary and model you provide.

The **only** outbound request is the optional AI summary, which is **off by default**. When you enable it, the transcript is sent to a **local Ollama instance on `localhost`** - it still never leaves your machine. If you don't enable summaries, no requests are made at all.

---

## Acknowledgements

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio
- Built on the [Obsidian API](https://github.com/obsidianmd/obsidian-api)

## License

[MIT](LICENSE) © Sergii Bataiev
