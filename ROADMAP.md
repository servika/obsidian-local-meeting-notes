# Roadmap

Planned and in-progress work for the **AI Meeting Notes** macOS app
(`packages/meeting-engine`). Items are grouped by theme and roughly ordered by
priority within each group. Nothing here is started unless marked otherwise.

See [CHANGELOG.md](CHANGELOG.md) for what's already shipped.

---

## Distribution & packaging

- **Bundle whisper.cpp into the app.**
  Today the app shells out to `whisper-cli` resolved by absolute path, so users
  must `brew install whisper-cpp`. Bundle the binary (and a default model, or
  first-run download) so the app has no external dependency.
- **Developer ID signing + notarization + DMG.**
  Scripts already exist (`scripts/build-app.sh`, `scripts/make-dmg.sh`,
  `scripts/app.entitlements`) and are env-var gated on `DEVELOPER_ID_APP` /
  `NOTARY_PROFILE`. Blocked on enrolling in the Apple Developer Program
  ($99/yr). Until then the app is ad-hoc signed (Gatekeeper warning on other
  Macs). Mac App Store is ruled out - the sandbox forbids process-tap
  system-audio capture and shelling out to `whisper-cli`.
- **Swift CI.**
  `.github/workflows/build.yml` only builds the Obsidian plugin. Add a macOS
  job that builds the Swift package and the `.app`.

## Summary quality

- **Bake a tuned Llama prompt.**
  `AppSettings.llamaPrompt` is still a placeholder; replace it with a real
  tuned prompt.
- **Add a tuned Qwen default prompt.**
  `qwen2.5:14b` currently falls back to the generic prompt. Add a
  `qwen`-matched default in `AppSettings.defaultPrompt(for:)` and run an A/B
  (gpt-oss vs qwen) on a real transcript to compare quality, especially for
  Ukrainian.
- **Decide on `noteQualityBaseline`.**
  Currently `0.3.0`. The temperature-0 determinism fix (0.4.1) improved
  reliability without changing structure - decide whether to bump the baseline
  so pre-0.4.1 notes surface the "re-generate" prompt.

## Capture & product (the "Notion-grade" roadmap)

- **Auto-start recording.**
  Detect meetings via Calendar (EventKit) and start/stop capture
  automatically.
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
- **Language picker: drop Auto-detect?**
  Open question - whether to force an explicit English/Ukrainian choice for
  best transcription quality.