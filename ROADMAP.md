# Roadmap

Planned and in-progress work for the **AI Meeting Notes** macOS app
(`packages/meeting-engine`). Items are grouped by theme and roughly ordered by
priority within each group. Nothing here is started unless marked otherwise.

See [CHANGELOG.md](CHANGELOG.md) for what's already shipped.

---

## Distribution & packaging

- **Developer ID signing + notarization + DMG.**
  Scripts already exist (`scripts/build-app.sh`, `scripts/make-dmg.sh`,
  `scripts/app.entitlements`) and are env-var gated on `DEVELOPER_ID_APP` /
  `NOTARY_PROFILE`. Blocked on enrolling in the Apple Developer Program
  ($99/yr). Until then the app is ad-hoc signed (Gatekeeper warning on other
  Macs). Mac App Store is ruled out - the sandbox forbids process-tap
  system-audio capture and shelling out to `whisper-cli`.

## Summary quality

- ~~**Decide on `noteQualityBaseline`.**~~ ✅ Bumped to `0.15.0` (0.16.1). VAD
  (0.13), paragraph splitting (0.14), and the transcript timeline (0.15) changed
  note output, so notes generated before 0.15.0 now surface the "re-generate"
  prompt.

## Capture & product (the "Notion-grade" roadmap)

- **localhost API + Obsidian plugin integration.**
  The original hybrid plan: native app as the capture/transcription daemon,
  the Obsidian plugin as a client that reads/queries meetings.
- **Real multi-speaker diarization.**
  Go beyond the current track-based You/Them split to identify individual speakers.
- **Chat over meetings (RAG).**
  Ask questions across the meeting archive.
 
## Security & polish

- **Keychain for the Claude API key.**
  Currently stored in UserDefaults as plaintext; move it to the Keychain.
- **Add more meeting languages.**
  Keep **Auto-detect** as an option (decided - it stays). Expand the explicit
  language list in `meetingLanguages` beyond English/Ukrainian in a future
  release, so users can pin other languages for best transcription quality.

## Postponed

- **Windows / cross-platform app.** Postponed. The current macOS app can't be
  ported directly: SwiftUI, Core Audio process taps (zero-setup system-audio
  capture), and AVFoundation are Apple-only. whisper.cpp and the Ollama/Claude
  summarization logic are cross-platform. Options when revisited:
  1. Windows users use the **Obsidian plugin** today + a loopback device
     (Stereo Mix / VB-Audio Cable) for system audio.
  2. A **cross-platform rewrite** (e.g. Tauri) reusing whisper + summarization,
     reimplementing capture with WASAPI loopback (system) and WASAPI (mic), and
     a single shared UI for macOS + Windows - preferred over a Windows-only fork.
