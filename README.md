# Local Meeting Notes

> Record meetings - **your microphone + the other participants' audio** - and transcribe them **100% locally** with [whisper.cpp](https://github.com/ggerganov/whisper.cpp). No cloud, no API keys, no companion server. Your audio never leaves your machine.

![status: alpha](https://img.shields.io/badge/status-alpha-orange) ![platform: desktop](https://img.shields.io/badge/platform-desktop-blue) ![license: MIT](https://img.shields.io/badge/license-MIT-green)

Most Obsidian transcription plugins either send your audio to a cloud API, capture **only your microphone** (missing everyone else on the call), or require you to stand up a separate transcription server. Local Meeting Notes does none of that: it mixes your mic with system audio in-process, resamples in the browser (no `ffmpeg`), and shells out to a local `whisper.cpp` binary.

---

## Why this plugin

- 🔒 **Fully local & private.** Transcription runs on your machine via `whisper.cpp`. Nothing is uploaded.
- 🎙️ **Captures the whole meeting.** Mixes your mic with the call's system audio (the other participants), not just you.
- 🪶 **Zero infrastructure.** No companion server, no bundled multi-hundred-MB model, no `ffmpeg` - audio is resampled to whisper's format in-browser via `OfflineAudioContext`.
- 📝 **Straight into your vault.** A timestamped Markdown note with frontmatter and the transcript, with the audio optionally saved alongside.

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
2. BRAT → **Add Beta Plugin** → `servika/obsidian-local-meeting-notes`.
3. Enable **Local Meeting Notes** in **Settings → Community plugins**.

### Manual

1. Download `main.js`, `manifest.json`, and `versions.json` from the [latest release](https://github.com/servika/obsidian-local-meeting-notes/releases).
2. Copy them into `<your-vault>/.obsidian/plugins/local-meeting-notes/`.
3. Reload Obsidian and enable the plugin under **Settings → Community plugins**.

---

## Setup in Obsidian

Open **Settings → Local Meeting Notes**:

1. Click **Grant** to allow microphone access (needed once so device names appear).
2. Choose your **Microphone** and your **System audio (loopback)** device (e.g. *BlackHole 2ch*).
3. Set **Model path** to your model file, e.g. `~/models/ggml-base.en.bin`.
4. The **whisper-cli binary** defaults to `whisper-cli` (works if installed via Homebrew); override with a full path if needed.

---

## Usage

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

---

## Troubleshooting

- **"whisper model not found"** - set the **Model path** to the absolute path of your `.bin` file. `~` is expanded.
- **Device names are blank** - click **Grant** in settings to authorize microphone access, then reopen settings.
- **Only my voice is transcribed** - your system-audio device isn't selected, or the call's audio isn't routed through BlackHole. Check your macOS output device / Multi-Output Device.
- **Transcription is slow** - use a smaller model (`base.en`/`small.en`), or pass more threads. Apple Silicon transcribes `base` far faster than realtime.
- **Plugin doesn't appear after install** - reload Obsidian (Cmd-R) or toggle Community plugins off/on.

---

## Development

```bash
git clone https://github.com/servika/obsidian-local-meeting-notes
cd obsidian-local-meeting-notes
npm install
npm run dev     # watch build → main.js
npm run build   # type-check + production build
```

For live iteration, symlink the repo into a test vault:

```bash
ln -s "$(pwd)" "<your-vault>/.obsidian/plugins/local-meeting-notes"
```

Source layout:

| File | Role |
|---|---|
| `src/main.ts` | Plugin entry - commands, ribbon, orchestration |
| `src/recorder.ts` | Captures + mixes mic and system audio via Web Audio |
| `src/wav.ts` | Resamples to 16 kHz mono WAV (no ffmpeg) |
| `src/transcription.ts` | Spawns `whisper-cli`, reads the transcript |
| `src/settings.ts` | Settings tab |

---

## Roadmap

- [ ] AI summary & action items from the transcript (local LLM via Ollama, or Claude)
- [ ] Near-live transcription (rolling chunks)
- [ ] Speaker diarization
- [ ] Linux / Windows loopback setup guides

---

## Privacy

This plugin makes **no network requests**. Audio is recorded, resampled, and transcribed entirely on your device. The only external programs invoked are the `whisper.cpp` binary and your model file, both of which you provide and which run locally.

---

## Acknowledgements

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio
- Built on the [Obsidian API](https://github.com/obsidianmd/obsidian-api)

## License

[MIT](LICENSE) © Sergii Bataiev