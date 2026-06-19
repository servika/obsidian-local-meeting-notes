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

- **Meeting category (1:1, daily sync, planning, …).**
  Add a `category:` frontmatter field (NOT `type:` - that's already
  `type: meeting`). Levels, in order of value:
  1. **Label only** - a dropdown (presets + custom) for organizing / searching /
     Dataview queries.
  2. **Per-category summary prompts** - the real win: tailor the summary to the
     type (1:1 → action items + growth notes; standup → updates + blockers;
     planning → decisions + owners; interview → candidate signals). Reuses the
     existing per-model prompt machinery.
  3. **Auto-detect** - infer the category from the calendar event title (once
     calendar integration lands) or via an LLM classification. Defer.

## Capture & product (the "Notion-grade" roadmap)

- ✅ **Tighter Obsidian note integration.** Shipped in 0.17.0. Notes now
  embed both audio tracks (`![[… .mic.wav]]` / `… .system.wav`) in an Audio
  section so Obsidian shows inline players, and carry `tags: [meeting]` for
  querying (alongside the existing `type: meeting`). The app hides the Audio
  section (it accesses recordings directly). Possible follow-up: auto-fill a
  `participants` field once real speaker identification exists.
- **localhost API + Obsidian plugin integration.**
  The original hybrid plan: native app as the capture/transcription daemon,
  the Obsidian plugin as a client that reads/queries meetings.
- **Real multi-speaker diarization.**
  Go beyond the current track-based You/Them split to identify individual
  speakers. The two-track setup helps: the **mic track is already cleanly
  "You"**, so only the **system track** (remote participants) needs diarizing.

  Pipeline:
  1. **Segmentation** - detect speaker-change boundaries on the system track.
  2. **Speaker embeddings** - a voice-fingerprint vector per segment.
  3. **Clustering** - group segments into N speakers (auto-estimate count, or let
     the user set it).
  4. **Merge** - align speaker spans with whisper's timestamped segments (we
     already have per-segment timestamps) so each transcript line gets a speaker.

  **Tech:** bundle **sherpa-onnx** (ONNX Runtime, C++) - does segmentation +
  embeddings + clustering, ships as a native binary + small ONNX models (same
  pattern as the bundled `whisper-cli` and Silero VAD), offline/privacy-safe.
  Rejected: pyannote.audio (drags in Python + PyTorch); whisper.cpp `--diarize`
  (English-only turn detection via tinydiarize - useless for Ukrainian).

  **Caveats:** accuracy varies on real meeting audio (compression, varied remote
  mics, overlapping speech - "good not perfect"); unknown speaker count; naming
  is a *separate* problem (diarization yields "Speaker 1/2/3", not names).

  **Phased plan:**
  1. Diarize the system track into `Them 1 / Them 2 / …`; keep "You" from the mic
     track. Ships the core value.
  2. UI to **rename speakers** per meeting (and persist the mapping).
  3. Auto-name from **calendar attendees** / LLM inference, once those land.
  Worth a small prototype spike first: run sherpa-onnx on an existing
  `*.system.wav` to gauge real-world accuracy before committing.
- **Chat over meetings (RAG).**
  Ask questions across the meeting archive.
 
## Security & polish

- ✅ **Estimate transcription time (ETA).** Shipped. An up-front estimate from
  audio length × a **learned per-model end-to-end rate** (self-calibrating EMA,
  seeded by model size), shown counting down in the record panel and the meeting
  processing bar - covers transcription *and* the opaque summary phase. Replaced
  the 0.18.0 progress-extrapolation ETA, which couldn't see the summary phase.
  Rates persist in UserDefaults (`procRate.<model>`).
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
