# meeting-engine (Phase 1 spike)

Native macOS capture engine for the hybrid architecture - the eventual daemon
that captures meeting audio, transcribes, and diarizes, exposing a localhost API
to the Obsidian plugin (and future clients).

**Current status: core validated.** Captures macOS audio with **no virtual
device** (no BlackHole): two **separate tracks** - system audio (the other
participants) via Core Audio **process taps** (`AudioHardwareCreateProcessTap`,
macOS 14.4+) and your microphone via `AVAudioEngine`, one WAV each. System-audio
capture is confirmed working end-to-end via the signed app (incl. on Bluetooth
output). Remaining: harden the mic path, transcription + diarization, the
localhost API, and proper notarized distribution.

The capture pipeline is validated (mic captures real audio). System-audio capture
additionally requires the macOS **"Screen & System Audio Recording"** permission,
which **only a real signed app can request** - a CLI is silently denied. Hence the
two entry points below.

## Layout

- `Sources/MeetingEngineCore` - the reusable capture engine (`MeetingEngine.record`).
- `Sources/meeting-engine` - headless CLI for dev iteration of the pipeline.
  Cannot obtain the system-audio permission, so its system track stays silent.
- `Sources/MeetingEngineApp` - minimal AppKit app; the **signed bundle that can
  request the permission**.

## Build & run

**GUI app (needed for system-audio capture):**

```bash
cd packages/meeting-engine
./scripts/build-app.sh
open ".build/AI Meeting Notes.app"
```

A window appears with live System/Mic level meters. Click **Record** (Allow the
audio + microphone prompts on first use), hold your meeting, then **Stop &
Transcribe**. The app transcribes both tracks and writes a diarized
`Meeting <timestamp>.md` (You/Them) to your Desktop. Requires a whisper model at
`~/models/ggml-base.en.bin`. (Ad-hoc signed; distribution needs a Developer ID +
notarization.)

**CLI (dev iteration of the pipeline only):**

```bash
swift run meeting-engine 10 /tmp/meeting-test [appNameToTap]
```

## Why process taps (not ScreenCaptureKit / BlackHole)

- **No BlackHole / Multi-Output Device** - the whole point.
- **Audio-only** - taps don't require the scary "Screen Recording" permission that
  ScreenCaptureKit does.
- **Per-process** - taps can target specific apps (e.g. just Zoom/Teams), enabling
  cleaner diarization later by capturing the call separately from the mic.

## Roadmap (this package)

- [x] System-audio capture via process taps → WAV
- [x] Capture mic + system as separate tracks (free "me vs. them" diarization)
- [x] whisper.cpp transcription + You/Them diarization (`meeting-engine transcribe`)
- [ ] Auto-start (EventKit calendar + call-app detection)
- [ ] localhost HTTP/WebSocket API consumed by the Obsidian plugin
- [ ] Multi-speaker diarization (tinydiarize → sherpa-onnx embeddings)
- [ ] Codesign + notarize; Homebrew tap distribution

See the top-level project plan for the full architecture.