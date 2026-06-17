# meeting-engine (Phase 1 spike)

Native macOS capture engine for the hybrid architecture - the eventual daemon
that captures meeting audio, transcribes, and diarizes, exposing a localhost API
to the Obsidian plugin (and future clients).

**Current status: proof-of-concept.** This spike validates the single make-or-break
assumption: capturing macOS **system audio with no virtual device** (no BlackHole)
via Core Audio **process taps** (`AudioHardwareCreateProcessTap`, macOS 14.4+). It
taps the global system output, records for N seconds, and writes a WAV.

## Build & run

```bash
cd packages/meeting-engine
swift build
swift run meeting-engine 10 ~/Desktop/meeting-test.wav   # record 10s
```

The first run triggers a macOS permission prompt for audio capture (the embedded
`Info.plist` provides the usage strings). Grant it, **play some audio** (a video,
a call), and inspect the resulting WAV - it should contain that audio, captured
without any virtual-device setup.

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
- [ ] Capture mic + system as separate tracks (free "me vs. them" diarization)
- [ ] whisper.cpp transcription
- [ ] Auto-start (EventKit calendar + call-app detection)
- [ ] localhost HTTP/WebSocket API consumed by the Obsidian plugin
- [ ] Speaker diarization (tinydiarize → sherpa-onnx embeddings)
- [ ] Codesign + notarize; Homebrew tap distribution

See the top-level project plan for the full architecture.