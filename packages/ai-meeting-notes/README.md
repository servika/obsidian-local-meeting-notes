# AI Meeting Notes - Obsidian plugin (legacy)

> ⚠️ **Deprecated / not recommended.** The **[desktop apps](../../README.md)**
> (macOS & Windows) now do everything this plugin does - record, transcribe, and
> summarize - with **zero audio setup** (no loopback device) and a built-in
> meetings library. They write the same Markdown notes into any folder, including
> an Obsidian vault. Use a desktop app instead; this plugin is kept for the
> record and for the pure-in-Obsidian workflow, but isn't actively developed.

Records meetings (your mic + system audio) inside Obsidian and transcribes them
**100% locally** with [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
Output is the standard [meeting note format](../../NOTE-FORMAT.md).

> **Desktop only.** Capturing system audio and running a local binary require
> Obsidian's desktop app.

## Why this plugin

- 🔒 **Fully local & private.** Transcription runs on your machine via `whisper.cpp`. Nothing is uploaded.
- 🎙️ **Captures the whole meeting.** Mixes your mic with the call's system audio (the other participants), not just you.
- 🪶 **Zero infrastructure.** No companion server, no bundled multi-hundred-MB model, no `ffmpeg` - audio is resampled to whisper's format in-browser via `OfflineAudioContext`.
- 📝 **Straight into your vault.** A timestamped Markdown note with frontmatter and the transcript, with the audio optionally saved alongside.
- 🤖 **Optional AI summary & action items.** Opt-in summarization via a local [Ollama](https://ollama.com) model - off by default.

## How it works

```
 Mic ─┐
      ├─► Web Audio mixer ─► MediaRecorder (WebM/Opus) ─► OfflineAudioContext
 Sys ─┘   (loopback)                                     (resample → 16 kHz mono WAV)
                                                                    │
                                                       whisper.cpp (whisper-cli)
                                                                    │
                                                         transcript ─► Markdown note
```

Transcription is **batch**: record the whole meeting, then transcribe on stop.

## Prerequisites (macOS)

This plugin orchestrates two external pieces you install once. It does **not** bundle them.

### 1. A loopback device for system audio

System audio capture on macOS requires a **loopback (virtual audio) device** -
install any one you prefer, then select it as the System audio input in settings.
So you can still **hear** the call, open **Audio MIDI Setup**, create a
**Multi-Output Device** containing both your speakers/headphones **and** your
loopback device, and select it as your system output. (Recording just your own
microphone? You can skip the loopback device entirely.)

### 2. whisper.cpp + a model

```bash
brew install whisper-cpp
mkdir -p ~/models
curl -L -o ~/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

Larger models (`small`, `medium`, `large-v3`) are more accurate but slower.

> **Linux/Windows:** the architecture is portable, but the loopback setup differs
> (e.g. PulseAudio/PipeWire monitor sources on Linux).

## Installation

### Via BRAT

1. Install the [BRAT](https://github.com/TfTHacker/obsidian42-brat) community plugin.
2. BRAT → **Add Beta Plugin** → `servika/ai-meeting-notes`.
3. Enable **AI Meeting Notes** in **Settings → Community plugins**.

### Manual

1. Download `main.js`, `manifest.json`, `versions.json` from the [latest release](https://github.com/servika/ai-meeting-notes/releases).
2. Copy them into `<your-vault>/.obsidian/plugins/ai-meeting-notes/`.
3. Reload Obsidian and enable the plugin under **Settings → Community plugins**.

## Setup in Obsidian

Open **Settings → AI Meeting Notes**:

1. Click **Grant** to allow microphone access (needed once so device names appear).
2. Choose your **Microphone** and your **System audio (loopback)** device.
3. Set **Model path** to your model file, e.g. `~/models/ggml-base.en.bin`.
4. The **whisper-cli binary** defaults to `whisper-cli`; override with a full path if needed.

> 📖 The [step-by-step usage guide](../../docs/USAGE.md) walks through the macOS
> audio routing (the part people get stuck on).

## Settings reference

| Setting | Default | Description |
|---|---|---|
| Microphone | - | Input device for your voice. |
| System audio (loopback) | - | The other participants (your loopback device). Leave empty for mic-only. |
| whisper-cli binary | `whisper-cli` | Command or absolute path to the whisper.cpp CLI. |
| Model path | - | Absolute path (or `~/…`) to a `ggml-*.bin` model. |
| Language | `auto` | Language code (e.g. `en`) or `auto`. |
| Transcripts folder | `Meetings` | Vault folder for transcript notes. |
| Save audio file | `true` | Keep the recorded audio in the vault. |
| Recordings folder | `Meetings/recordings` | Where saved audio goes. |
| Generate summary | `false` | Run each transcript through a local LLM for a summary + action items. |
| Ollama URL | `http://localhost:11434` | Base URL of your local Ollama server. |
| Ollama model | - | Model name from `ollama list`. |
| Summary prompt | *(built-in)* | Prompt template; `{{transcript}}` is replaced with the text. |

## Troubleshooting

- **"whisper model not found"** - set **Model path** to the absolute path of your `.bin` file.
- **Device names are blank** - click **Grant** in settings, then reopen settings.
- **Only my voice is transcribed** - your system-audio device isn't selected, or the call's audio isn't routed through your loopback device.
- **Transcription is slow** - use a smaller model (`base.en`/`small.en`).
- **Plugin doesn't appear after install** - reload Obsidian (Cmd-R) or toggle Community plugins off/on.

## Development

```bash
cd packages/ai-meeting-notes
npm install
npm run dev     # watch build → main.js
npm run build   # type-check + production build
```

| File | Role |
|---|---|
| `src/main.ts` | Plugin entry - commands, ribbon, orchestration |
| `src/recorder.ts` | Captures + mixes mic and system audio via Web Audio |
| `src/wav.ts` | Resamples to 16 kHz mono WAV (no ffmpeg) |
| `src/transcription.ts` | Spawns `whisper-cli`, reads the transcript |
| `src/settings.ts` | Settings tab |

## Privacy

By default this plugin makes **no network requests**. Audio is recorded,
resampled, and transcribed entirely on your device. The **only** optional
outbound request is the AI summary (off by default), which goes to a **local
Ollama instance on `localhost`** - it still never leaves your machine.