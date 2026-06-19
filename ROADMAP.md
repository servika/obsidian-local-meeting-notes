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

- ~~**Add a tuned Qwen default prompt.**~~ ✅ Shipped in 0.10.0. A/B finding:
  qwen2.5:14b produces excellent, well-structured summaries on *clean*
  transcripts (arguably better than gpt-oss), but on fragmented base-model
  Ukrainian ASR it refused/went chatty while gpt-oss tolerated the noise. The
  tuned `qwenPrompt` forbids refusals/preamble; the real Ukrainian fix is
  better transcription (use the `large-v3` per-language override).
- **Decide on `noteQualityBaseline`.**
  Currently `0.3.0`. The temperature-0 determinism fix (0.4.1) improved
  reliability without changing structure - decide whether to bump the baseline
  so pre-0.4.1 notes surface the "re-generate" prompt.

## Capture & product (the "Notion-grade" roadmap)

- **Auto-start recording.**
  - ✅ Shipped in 0.8.0: **suggest** recording when a meeting is detected (the
    mic goes in-use by another app, via Core Audio). A nudge appears; the user
    decides - it never records on its own.
  - Future: optional Calendar (EventKit) detection to nudge at a scheduled
    event's start and auto-fill the title, and a fully-automatic start/stop
    mode for users who want it.
- **localhost API + Obsidian plugin integration.**
  The original hybrid plan: native app as the capture/transcription daemon,
  the Obsidian plugin as a client that reads/queries meetings.
- **Real multi-speaker diarization.**
  Go beyond the current track-based You/Them split to identify individual
  speakers.
- **Chat over meetings (RAG).**
  Ask questions across the meeting archive.

## Security & polish

- **Keychain for the Claude API key.**
  Currently stored in UserDefaults as plaintext; move it to the Keychain.
- **Add more meeting languages.**
  Keep **Auto-detect** as an option (decided - it stays). Expand the explicit
  language list in `meetingLanguages` beyond English/Ukrainian in a future
  release, so users can pin other languages for best transcription quality.
