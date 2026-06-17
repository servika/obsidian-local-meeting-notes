# meeting-engine (Phase 1 spike)

Native macOS capture engine for the hybrid architecture - the eventual daemon
that captures meeting audio, transcribes, and diarizes, exposing a localhost API
to the Obsidian plugin (and future clients).

**Current status: proof-of-concept.** This spike validates the make-or-break
assumption: capturing macOS audio with **no virtual device** (no BlackHole). It
records two **separate tracks** - system audio (the other participants) via Core
Audio **process taps** (`AudioHardwareCreateProcessTap`, macOS 14.4+) and your
microphone via `AVAudioEngine` - writing one WAV each.

## Build & run

```bash
cd packages/meeting-engine
swift build
swift run meeting-engine 10 ~/Desktop/meeting-test   # 10s -> .system.wav + .mic.wav
```

The first run triggers macOS permission prompts for audio + microphone capture
(the embedded `Info.plist` provides the usage strings). Grant them, **play some
audio and talk**, then inspect the two WAVs - `*.system.wav` should hold the
played audio and `*.mic.wav` your voice, captured without any virtual-device setup.

If you see `⚠️ no audio frames were captured`, the permission was denied - grant
it under **System Settings → Privacy & Security** and re-run.

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