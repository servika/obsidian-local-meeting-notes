# Windows app - implementation plan

A native Windows port of **AI Meeting Notes**, in a new monorepo package
`packages/meeting-notes-windows/`. The macOS app (`packages/meeting-engine`) is
left untouched.

**Decisions (locked):**
- **Stack:** .NET 8 + C#.
- **Audio:** NAudio - `WasapiLoopbackCapture` (system audio, zero-setup, no
  virtual device - the macOS process-tap equivalent) + `WasapiCapture` (mic), as
  two separate WAV tracks.
- **UI:** WinUI 3 (Windows App SDK). WPF is an acceptable lower-friction
  fallback if WinUI tooling fights us.
- **Scope (v1 = MVP):** record → transcribe → summarize → Markdown note in the
  vault. Diarization, auto meeting-detection, tray UI, ETA, and the model
  downloader are deferred to post-MVP.

**Reused from macOS (logic only - re-implemented in C#, same behavior):**
`Transcriber` (whisper.cpp invocation + JSON parse + two-track You/Them merge),
`Summarizer` (Ollama `/api/generate` + Claude `/v1/messages`, map-reduce
chunking), `SummaryPrompts`, `MeetingStore` (Markdown + frontmatter + `![[…]]`
embeds), `AppSettings`. These are pure logic / HTTP / filesystem and port
directly.

**Rewritten (Apple-only on macOS):** `Recorder` (Core Audio taps → WASAPI),
`MeetingDetector` (deferred), SwiftUI UI.

---

## Phase 0 - Scaffolding

1. Create `packages/meeting-notes-windows/` with a .NET 8 solution
   `MeetingNotes.sln` and three projects:
   - `MeetingNotes.Core` (class library): settings, transcription, summarization,
     note storage - no Windows-UI dependency, unit-testable.
   - `MeetingNotes.Audio` (class library): WASAPI capture, depends on NAudio.
   - `MeetingNotes.App` (WinUI 3 packaged app): UI + wiring.
   - `MeetingNotes.Core.Tests` (xUnit).
2. NuGet: `NAudio`, `Microsoft.WindowsAppSDK` (WinUI 3). Use built-in
   `System.Text.Json` and `HttpClient` - no extra deps for HTTP/JSON.
3. CI sanity: `dotnet build` + `dotnet test` on `windows-latest` (GitHub Actions).

**Exit:** empty app launches; tests run green.

## Phase 1 - Audio capture (the core differentiator; do this first to de-risk)

1. `SystemAudioRecorder` using `WasapiLoopbackCapture` on the default render
   endpoint → `<base>.system.wav`.
2. `MicRecorder` using `WasapiCapture` on the default capture endpoint →
   `<base>.mic.wav`.
3. Write 16-bit PCM WAV via NAudio `WaveFileWriter`. Capture at device format,
   then resample to **16 kHz mono** (whisper's required input) with
   `MediaFoundationResampler` - either on the fly or as a post-step (replaces the
   macOS `afconvert`).
4. Live **peak level** per track from the `DataAvailable` buffer → expose an
   `OnLevel(system, mic)` callback for the UI VU meters.
5. `MeetingRecorder` façade: `Start(outBase)` / `Stop()` runs both concurrently,
   returns the two file paths + frame counts (mirror macOS `CaptureResult`).

**Known WASAPI gotchas to handle explicitly:**
- Loopback emits **no `DataAvailable` while the system is silent**; NAudio's
  `WasapiLoopbackCapture` papers over this but verify gaps don't desync the two
  tracks (pad with silence if needed so timestamps stay aligned).
- No default render device (headless/RDP) → clear error, mic-only fallback.
- Output-device switch mid-recording → catch and stop cleanly for v1.
- Sample-rate/format negotiation differs per device → always normalize to 16 kHz
  mono before whisper.

**Exit:** a 30-second test produces two correct, in-sync 16 kHz mono WAVs; level
callback moves.

## Phase 2 - Transcription

1. Bundle `whisper-cli.exe` (whisper.cpp Windows build; CPU baseline, optional
   Vulkan/CUDA later) + the Silero VAD model under the app's resources.
2. `Transcriber.Transcribe(wav, model, language)`: run
   `whisper-cli -m <model> -f <16k.wav> -l <lang> -oj -of <base>
   --suppress-nst [--vad --vad-model …]`, parse the `-oj` JSON into segments.
3. Port `diarizedMarkdown`: interleave the two tracks' segments by timestamp into
   a **You / Them** labeled transcript (free 2-speaker split, no model).
4. Stream whisper stderr to a progress callback (port the percent parse).

**Exit:** a recorded meeting yields a labeled transcript matching macOS output.

## Phase 3 - Summarization (near-direct port)

1. `Summarizer` with `SummaryEngine` = Ollama | Claude.
   - Ollama: `POST {url}/api/generate`, `temperature 0`, `keep_alive 0`.
   - Claude: `POST https://api.anthropic.com/v1/messages`, `x-api-key`,
     `anthropic-version: 2023-06-01`. **Re-read the latest model IDs / params via
     the claude-api skill when implementing - don't copy stale values.**
2. Port map-reduce chunking (split >~40k chars into ~24k chunks → map → reduce).
3. Port `SummaryPrompts` (per-model default prompts + overrides).
4. `OllamaClient.InstalledModels()` via `/api/tags` for the settings picker.

**Exit:** transcript → summary + action items via both engines.

## Phase 4 - Note storage (direct port)

1. `MeetingStore`: write `<vault>/<MeetingsFolder>/<title>.md` with the same
   frontmatter (`type: meeting`, `tags: [meeting]`, `speakers:` etc.), Summary /
   Action items / Transcript sections, and `![[….mic.wav]]` / `….system.wav`
   embeds; copy audio to the recordings subfolder.
2. Reuse the macOS note format verbatim so notes are interchangeable across OSes.

**Exit:** a finished meeting appears as a correct note in an Obsidian vault.

## Phase 5 - UI (WinUI 3)

1. Main window: **Record / Stop** button, live system+mic level meters, meeting
   list (left), detail pane (summary, action items, transcript) on the right.
2. Settings: vault folder picker, whisper model path/picker, language (`auto`
   default), summary engine (Ollama URL+model / Claude key+model), processing-step
   toggles (transcribe / summarize) mirroring macOS.
3. Wire to `MeetingRecorder` → `Transcriber` → `Summarizer` → `MeetingStore`,
   off the UI thread with progress + cancellation.

**Exit:** full record→note loop driven entirely from the UI.

## Phase 6 - Packaging & distribution

1. `dotnet publish` self-contained (win-x64, also arm64 if feasible), bundling
   `whisper-cli.exe` + VAD model.
2. Installer: **MSIX** (clean install/update, Store-ready) or **Inno Setup / WiX**
   for a classic `.exe`/`.msi`. Pick MSIX unless it blocks the bundled native exe.
3. **Code signing (Authenticode)** - the Windows analogue of Apple notarization.
   Options: an OV/EV cert (~$200-400/yr) or **Azure Trusted Signing** (~$10/mo,
   simplest now). Unsigned builds trip **SmartScreen** until reputation builds.
4. Publish as a GitHub Release asset; add a Windows download button to the
   `docs/` landing page (mirror the macOS `releases/latest/download` pattern).

**Exit:** a signed installer that runs on a clean Windows 11 machine.

## Phase 7 - Post-MVP (deferred, in priority order)

- **Speaker diarization** - sherpa-onnx Windows binary + ONNX models (port
  `Diarizer`).
- **Auto meeting-detection** - detect Zoom/Teams/Meet using the mic via
  `IAudioSessionManager2` session enumeration (macOS `MeetingDetector` equivalent).
- **System-tray app** with quick record control + "suggest recording" nudge.
- **ETA** (port the self-calibrating EMA rate estimate).
- **Model downloader** in-app (HuggingFace ggml models; port `ModelDownloader`).
- **Auto-update** check against GitHub Releases.

---

## Risks / open questions

- **WASAPI loopback fidelity** is the make-or-break item - Phase 1 is
  intentionally first. If two-track sync proves fragile, fall back to a single
  mixed loopback track (lose the free You/Them split but keep capture).
- **whisper.cpp Windows GPU**: ship CPU first; add Vulkan/CUDA builds later for
  speed.
- **WinUI 3 vs WPF**: if WinUI packaging fights the bundled native `whisper-cli`,
  switch the App project to WPF - Core/Audio libraries are UI-agnostic, so only
  the App project changes.
- **Signing cost/lead time**: start Azure Trusted Signing setup early (parallel
  with Phase 1-2) so Phase 6 isn't blocked.