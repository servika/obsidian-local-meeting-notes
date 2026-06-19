# Changelog

All notable changes are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This repo ships two apps, versioned independently:

- **macOS app** - `packages/meeting-engine` (version in `packages/meeting-engine/VERSION`)
- **Obsidian plugin** - `packages/ai-meeting-notes` (version in its `manifest.json`)

---

## macOS app

### [0.14.0] - 2026-06-19

#### Changed
- **Readable transcripts.** Long monologues are now broken into paragraphs (on
  speech pauses and at sentence boundaries) instead of one giant block. In the
  app, continuation paragraphs are indented under the speaker. Applies to new
  transcripts and re-generations.

### [0.13.1] - 2026-06-19

#### Fixed
- **Deleting a meeting no longer removes audio another note still uses.** Audio
  tracks are deleted only when no remaining note references that recording -
  preventing data loss when an older duplicate note shared the same audio.

### [0.13.0] - 2026-06-19

#### Added
- **Voice Activity Detection (VAD).** A small Silero VAD model is now bundled and
  used during transcription, plus `--suppress-nst`. This skips non-speech regions
  so whisper no longer hallucinates phrases like "Дякую за перегляд!" on silence,
  and it noticeably improves real transcription quality.
- **Default model is now a dropdown** of downloaded models (like the per-language
  setting), instead of a free-text path field.

#### Fixed
- **Renaming a meeting while recording created a duplicate note.** On finish, the
  recording now updates the (possibly renamed) note by matching its audio link,
  instead of recreating the original filename.

### [0.12.1] - 2026-06-19

#### Fixed
- **Empty Summary tab when the model skipped section headings.** If a summary
  came back as plain text without `## ` headings, the Summary tab showed nothing
  (while the Markdown tab showed the text). That leading content is now surfaced
  as a Summary section so it's always visible.

### [0.12.0] - 2026-06-19

#### Added
- **"Best quality for Ukrainian" preset** (Settings → Transcription → Quick
  setup). One click sets the language to Ukrainian and pins the `large-v3` model
  for it, downloading large-v3 first if it isn't present.

### [0.11.0] - 2026-06-19

#### Added
- **Vocabulary hint for transcription.** A new optional field (Settings →
  Transcription) is passed to whisper as an initial prompt (carried across the
  whole recording) to improve spelling of participant names, product/company
  names, jargon, and to reinforce the spoken language - especially helpful for
  Ukrainian.

### [0.10.0] - 2026-06-19

#### Added
- **Tuned Qwen prompt.** Qwen models (`qwen2.5` / `qwen3`) now get a dedicated
  strict prompt instead of the generic fallback. On messy speech-recognition
  transcripts the generic prompt made Qwen refuse or go chatty; the tuned prompt
  forbids that and enforces the four-section format with unchecked action-item
  boxes.

#### Fixed
- Generic fallback prompt said "three sections" but listed four; corrected to
  four, and hardened against refusals/preamble.

### [0.9.0] - 2026-06-18

#### Added
- **Menu bar item.** A status-bar icon reflects state at a glance (idle /
  recording / processing / meeting-detected) and its menu offers one-click
  Start/Stop, the "meeting detected" nudge, Open window, and Quit - so you can
  control recording even when the main window is closed or behind your call.

### [0.8.0] - 2026-06-18

#### Added
- **"Meeting detected" suggestion.** When another app (Zoom, Teams, Google
  Meet, FaceTime…) starts using your microphone, the record panel shows a
  gentle "Start recording?" nudge with Record / dismiss buttons. Detection uses
  Core Audio (`kAudioDevicePropertyDeviceIsRunningSomewhere`) - no new
  permissions - and **never records on its own**. Toggle in Settings → General
  (on by default).

### [0.7.1] - 2026-06-18

#### Changed
- **Tuned the default Llama prompt.** Replaced the placeholder `llamaPrompt`
  with a proper plain-instruction prompt (fixed "three"→"four" sections, You/Them
  roles, stronger no-preamble and no-invention rules) so Llama-family models
  reliably produce all four sections.

### [0.7.0] - 2026-06-18

#### Added
- **Bundled whisper.cpp** - the app now ships a self-contained, native
  `whisper-cli` inside the bundle (`Contents/Resources/whisper-cli`), so there's
  no longer any need to `brew install whisper-cpp`. Built statically and signed
  by `scripts/build-whisper.sh` (pinned to whisper.cpp v1.8.6); the transcriber
  prefers the bundled binary and only falls back to Homebrew/system paths for
  CLI and dev use.

### [0.6.1] - 2026-06-18

#### Added
- **Website link** (sergb.com) in the About tab, alongside GitHub and LinkedIn.

### [0.6.0] - 2026-06-18

#### Added
- **Model descriptions** under the download picker: size, speed/accuracy, and
  whether each model is multilingual or English-only (`.en`).
- **About tab links** to the project's GitHub and to the author's LinkedIn.

#### Changed
- **Taller summary-prompt editor** (min 300pt) so long prompts are easier to edit.

### [0.5.0] - 2026-06-18

#### Added
- **Per-language model is now a dropdown** of the whisper models you've
  downloaded (scanned from `~/models`), instead of typing a file path. A
  not-downloaded path still shows, marked "(missing)".

#### Changed
- **Settings is now tabbed** - General, Transcription, Summary, and About -
  instead of one long scrolling form.

### [0.4.2] - 2026-06-18

#### Changed
- Language picker limited to **Auto-detect, English, and Ukrainian** (also
  narrows the per-language model override options in Settings to match).

### [0.4.1] - 2026-06-18

#### Fixed
- **Missing summary sections** (e.g. *Topics discussed* not appearing): Ollama
  summarization now runs at `temperature: 0`, so the model deterministically
  emits every required section instead of occasionally dropping one.

### [0.4.0] - 2026-06-18

#### Added
- **Note version stamping**: each meeting note records the app version that
  generated it (`app_version` in the frontmatter).
- **Outdated-note prompts**: when a note was generated by a version older than
  the current quality baseline (`noteQualityBaseline`), the meeting shows a
  "Generated with an older version" banner with a one-click **Re-generate**
  action, and a ✨ marker appears on its row in the list. Bump
  `noteQualityBaseline` in a release whenever generated-note output changes.

### [0.3.2] - 2026-06-18

#### Changed
- **Topics discussed** now renders each topic as a larger, clearly separated
  block - numbered badge, prominent heading, accent bar, and a tinted
  background - so topics stand apart from the summary prose.

### [0.3.1] - 2026-06-18

#### Changed
- Meeting duration is now shown in plain words (e.g. `10 min 10 sec`,
  `1 hr 5 min 0 sec`) instead of a `mm:ss` clock format.

### [0.3.0] - 2026-06-18

#### Added
- **Per-language whisper models**: assign a specific model to a language (e.g.
  `large-v3` for Ukrainian) in Settings. Meetings in that language use the
  assigned model; all others fall back to the default model path.
- **`large-v3`** added to the in-app downloadable model list (full large model,
  alongside `large-v3-turbo`).

### [0.2.0] - 2026-06-18

#### Added
- **Meeting-language picker** on the record panel for better transcription
  quality; whisper is pinned to the chosen language instead of auto-detecting.
- **Topic blocks** in the summary: *Topics discussed* now renders each topic as
  an accent-barred block with a heading and 1-3 paragraphs/bullets.
- **Total meeting duration** stored in the note frontmatter and shown in the
  meetings list and meeting header.
- **State-aware row icons** distinguishing recording, processing, and idle
  meetings.

#### Changed
- Clicking **Record** now creates and selects a new meeting in the list
  immediately, so it's no longer confused with a previously highlighted note.
- Russian removed from the language options.

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