# Changelog

All notable changes are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This repo ships two apps, versioned independently:

- **macOS app** - `packages/meeting-engine` (version in `packages/meeting-engine/VERSION`)
- **Obsidian plugin** - `packages/ai-meeting-notes` (version in its `manifest.json`)

---

## macOS app

### [0.1.0] - 2026-06-18

First release of the standalone macOS app.

#### Added
- **Zero-setup capture** of system audio **and** microphone via Core Audio
  process taps - no BlackHole or Multi-Output Device. The two sides are recorded
  as **separate tracks** (works with Bluetooth output).
- **Local transcription** via `whisper.cpp`, with **automatic language detection**
  using a multilingual model.
- **"You vs. Them" diarization** derived from the separate tracks (no model).
- **AI summary** with four sections - *Short summary*, *Summary*,
  *Topics discussed*, *Action items* - via a local **Ollama** model or the
  **Claude API**, with **per-model prompts**.
- **Meetings library**: sidebar list + tabbed detail (**Summary / Transcript /
  Markdown**), written into your **Obsidian vault**.
- **Rename**, **re-generate**, and **delete** meetings; **copy** a note as Markdown.
- Live **System/Mic level meters**, a determinate **progress bar** + elapsed time,
  and **stop/cancel** processing (cancelled recordings stay re-generatable).
- **In-app whisper model download**; configurable storage folder, model, language,
  and summary engine/prompt.
- App **icon** and a signed **`.dmg`** build with Developer ID + notarization hooks.

---

## Obsidian plugin

### [0.1.0] - 2026-06-12

#### Added
- Record microphone + system audio (e.g. BlackHole) via the Web Audio API, kept as a stereo split (mic left, system right) to preserve speaker separation.
- In-browser resampling to 16 kHz mono WAV via `OfflineAudioContext` (no `ffmpeg`).
- Local transcription by shelling out to a `whisper.cpp` binary (`whisper-cli`).
- Transcript written to a timestamped Markdown note with frontmatter; optional saved audio.
- Settings tab: device pickers, whisper binary/model paths, language, output folders.
- Ribbon icon, status-bar recording indicator, and start/stop/toggle commands.
- Optional AI summary & action items via a local Ollama LLM (opt-in, off by default).