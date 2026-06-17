# meeting-engine (Phase 1 spike)

Native macOS capture engine for the hybrid architecture - the eventual daemon
that captures meeting audio, transcribes, and diarizes, exposing a localhost API
to the Obsidian plugin (and future clients).

**Current status: proof-of-concept.** Captures macOS audio with **no virtual
device** (no BlackHole): two **separate tracks** - system audio (the other
participants) via Core Audio **process taps** (`AudioHardwareCreateProcessTap`,
macOS 14.4+) and your microphone via `AVAudioEngine`, one WAV each.

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
open ".build/Meeting Engine.app"
```

A window appears - click **Record**, **Allow** the audio prompt when it appears,
then play audio + talk. Output goes to `~/Desktop/meeting-engine-app.{system,mic}.wav`.
(Ad-hoc signed; distribution needs a Developer ID + notarization.)

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
- [ ] whisper.cpp transcription
- [ ] Auto-start (EventKit calendar + call-app detection)
- [ ] localhost HTTP/WebSocket API consumed by the Obsidian plugin
- [ ] Speaker diarization (tinydiarize → sherpa-onnx embeddings)
- [ ] Codesign + notarize; Homebrew tap distribution

See the top-level project plan for the full architecture.