# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Near-live (chunked) transcription
- Speaker diarization
- Linux / Windows loopback setup guides

## [0.1.0] - 2026-06-12

### Added
- Record microphone + system audio (e.g. BlackHole) via the Web Audio API, kept as a stereo split (mic on the left channel, system on the right) to preserve speaker separation in the saved audio.
- In-browser resampling to 16 kHz mono WAV via `OfflineAudioContext` (no `ffmpeg` dependency).
- Local transcription by shelling out to a `whisper.cpp` binary (`whisper-cli`).
- Transcript written to a timestamped Markdown note with frontmatter; optional saved audio.
- Settings tab: device pickers, whisper binary/model paths, language, output folders.
- Ribbon icon, status-bar recording indicator, and start/stop/toggle commands.
- Optional AI summary & action items via a local Ollama LLM (opt-in, off by default; configurable URL, model, and prompt). The transcript is preserved even if summarization fails.

[Unreleased]: https://github.com/servika/ai-meeting-notes/compare/0.1.0...HEAD
[0.1.0]: https://github.com/servika/ai-meeting-notes/releases/tag/0.1.0