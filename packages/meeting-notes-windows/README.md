# AI Meeting Notes - Windows

Native Windows port of [AI Meeting Notes](../../README.md). Records a meeting
(system audio + your mic, no virtual device), transcribes it locally with
whisper.cpp, and summarizes it into a Markdown note in your Obsidian vault.

Status: **in development** (MVP). See [../../WINDOWS-PLAN.md](../../WINDOWS-PLAN.md).

## Layout

| Project | Target | Builds on |
|---|---|---|
| `src/MeetingNotes.Core` | `net8.0` | any OS (incl. macOS dev box) |
| `src/MeetingNotes.Audio` | `net8.0-windows` | Windows only (CI / your PC) |
| `src/MeetingNotes.App` | WinUI 3 (added in Phase 5) | Windows only |
| `tests/MeetingNotes.Core.Tests` | `net8.0` | any OS |

`Core` is pure portable logic (transcription orchestration, Ollama/Claude
summarization, note storage, settings) and is unit-tested cross-platform. The
Windows-only projects build on the `windows-latest` GitHub Actions runner.

## Build & test

```bash
# Portable Core (works on macOS/Linux/Windows)
dotnet build src/MeetingNotes.Core/MeetingNotes.Core.csproj
dotnet test  tests/MeetingNotes.Core.Tests/MeetingNotes.Core.Tests.csproj

# Full solution (Windows only - needs the net8.0-windows targeting pack)
dotnet build MeetingNotes.sln
```

Requires the .NET 8 SDK.

## Whisper setup

The app needs `whisper-cli.exe` and a ggml model (`.bin`):

- **Model** - click **Download** in Settings (pick `base` to start); it lands in
  `%APPDATA%/MeetingNotes/models/`. Or Browse to an existing `.bin`.
- **whisper-cli.exe** - bundle it once with `pwsh ./scripts/setup-whisper.ps1`
  (downloads the latest whisper.cpp Windows binary into `src/MeetingNotes.App/vendor/`,
  copied next to the app on build and auto-resolved). Or Browse to your own copy.