# Roadmap

Planned and in-progress work for the **AI Meeting Notes** macOS app
(`packages/meeting-engine`). Items are grouped by theme and roughly ordered by
priority within each group. Nothing here is started unless marked otherwise.

See [CHANGELOG.md](CHANGELOG.md) for what's already shipped.

---

## Known bugs

_None currently._

(Fixed: "processing bar showed on the wrong meeting" - 0.21.1 scopes the busy UI
to `controller.activeID == meeting.id`.)

(Fixed: "model stays in memory after processing" - 0.21.3 sends `keep_alive: 0`
so Ollama unloads the summary model right after summarizing; whisper-cli already
exits after each transcription.)

## Distribution & packaging

- **Developer ID signing + notarization + DMG.**
  Scripts already exist (`scripts/build-app.sh`, `scripts/make-dmg.sh`,
  `scripts/app.entitlements`) and are env-var gated on `DEVELOPER_ID_APP` /
  `NOTARY_PROFILE`. Blocked on enrolling in the Apple Developer Program
  ($99/yr). Until then the app is ad-hoc signed (Gatekeeper warning on other
  Macs). Mac App Store is ruled out - the sandbox forbids process-tap
  system-audio capture and shelling out to `whisper-cli`.
- **Check for a new version.**
  Let the app notice when a newer release is available and tell the user
  (with a link / one-click update). Compare the running `VERSION` against the
  latest published release (e.g. the GitHub Releases API or a small hosted
  version manifest), check on launch (throttled) and on demand, and surface an
  unobtrusive "update available" prompt. Keep it privacy-safe: a single
  outbound check, no telemetry. Pairs with proper signing/notarization above so
  the downloaded update isn't Gatekeeper-blocked.

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

- **localhost API + Obsidian plugin integration.**
  The original hybrid plan: native app as the capture/transcription daemon,
  the Obsidian plugin as a client that reads/queries meetings.
- **Real multi-speaker diarization** (phase 1 shipped in 0.23.0 as the
  experimental "Recognize speakers" toggle - see Completed). Remaining phases:
  - **Phase 2:** UI to **rename speakers** per meeting (and persist the mapping).
  - **Phase 3:** Auto-name from **calendar attendees** / LLM inference, once those land.

  Other follow-ups now that the pipeline exists: ~~let the user pin the speaker
  count~~ (done in 0.25.0 - per-meeting count, since auto-estimate proved
  unreliable on real audio), expose the clustering threshold, try a better
  embedding model (wespeaker over-split least in testing), and fold the mic
  "You" track into the embedding space so a remote echo of the user isn't
  counted as a separate "Them".
- **Chat over meetings (RAG).**
  Ask questions across the meeting archive.

## Security & polish

- **Keychain for the Claude API key.**
  Currently stored in UserDefaults as plaintext; move it to the Keychain.
- **Add more meeting languages.**
  Keep **Auto-detect** as an option (decided - it stays). Expand the explicit
  language list in `meetingLanguages` beyond English/Ukrainian in a future
  release, so users can pin other languages for best transcription quality.

## Completed

See [CHANGELOG.md](CHANGELOG.md) for the full shipped history. Highlights:

- ✅ **Map-reduce summarization for long meetings.** Shipped in 0.22.0.
  Transcripts over ~40k chars are split into ~24k-char chunks (fits even modest
  context windows), each summarized into partial notes (map), then combined into
  the final summary (reduce). Even coverage regardless of length, and smaller
  models can handle long meetings. The model is kept loaded between chunks
  (`keep_alive` during map) and unloaded after the final pass. Possible
  follow-up: recursive reduce if the combined partials themselves get large.
- ✅ **Per-stage processing controls.** Shipped in 0.24.0. Settings →
  "Processing steps" toggles for Transcribe and Summarize, each disabled with an
  inline note when its dependency is missing (no whisper model → no
  transcription; no local model / Claude key → no summary). Replaced the summary
  engine "None" option (migrated to the toggle).
- ✅ **Experimental mode + per-meeting speaker count.** Shipped in 0.25.0. A
  master "Experimental features" switch gates R&D features (off by default).
  Speaker recognition now lets you set the exact number of remote speakers per
  meeting (stored in `speakers:` frontmatter), since auto-detect proved
  unreliable on real audio.
- ✅ **Multi-speaker diarization - phase 1 (experimental).** Shipped in 0.23.0
  as the "Recognize speakers" toggle. Runs sherpa-onnx (segmentation + speaker
  embeddings + clustering, native/offline) on the **system track** and relabels
  whisper's segments by time overlap into `Them 1 / Them 2 / …`; the mic track
  stays "You". Off by default; the toggle is disabled until the binary + ONNX
  models are installed (`scripts/setup-diarization.sh`), bundled into the app
  when present. Threshold-based clustering auto-estimates the speaker count.
  Remaining phases (rename UI, calendar/LLM auto-naming) are under Capture &
  product.
- ✅ **Tighter Obsidian note integration.** Shipped in 0.17.0. Notes now
  embed both audio tracks (`![[… .mic.wav]]` / `… .system.wav`) in an Audio
  section so Obsidian shows inline players, and carry `tags: [meeting]` for
  querying (alongside the existing `type: meeting`). The app hides the Audio
  section (it accesses recordings directly). Possible follow-up: auto-fill a
  `participants` field once real speaker identification exists.
- ✅ **Estimate transcription time (ETA).** Shipped. An up-front estimate from
  audio length × a **learned per-model end-to-end rate** (self-calibrating EMA,
  seeded by model size), shown counting down in the record panel and the meeting
  processing bar - covers transcription *and* the opaque summary phase. Replaced
  the 0.18.0 progress-extrapolation ETA, which couldn't see the summary phase.
  Rates persist in UserDefaults (`procRate.<model>`).

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
