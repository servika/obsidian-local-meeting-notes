# Contributing

Thanks for your interest in improving Local Meeting Notes! This is an early-stage,
desktop-only Obsidian plugin and contributions are very welcome - especially
**Linux and Windows loopback support**, which the author can't test on macOS.

## Getting started

The plugin lives in `packages/local-meeting-notes/`.

```bash
git clone https://github.com/servika/obsidian-local-meeting-notes
cd obsidian-local-meeting-notes/packages/local-meeting-notes
npm install
npm run dev   # watch build → main.js
```

Symlink the **package** directory into a **test vault** (not your main one) and enable the plugin:

```bash
# from packages/local-meeting-notes
ln -s "$(pwd)" "<test-vault>/.obsidian/plugins/local-meeting-notes"
```

Reload Obsidian (Cmd-R) after each build, or toggle the plugin off/on.

## Before opening a PR

- Run `npm run build` - it type-checks (`tsc -noEmit`) and produces a production `main.js`. CI will fail if this fails.
- Keep changes focused; match the existing code style (tabs, no semicolon-free style - follow the surrounding files).
- Do **not** commit `main.js` or `node_modules` (both are gitignored). Releases build `main.js` from CI.
- Update `CHANGELOG.md` under `[Unreleased]`.

## Reporting bugs

Open an issue with:
- Your OS and Obsidian version
- The whisper.cpp binary/model you're using
- Steps to reproduce and any console output (Cmd-Opt-I → Console)

## Architecture

| File | Role |
|---|---|
| `src/main.ts` | Plugin entry - commands, ribbon, orchestration |
| `src/recorder.ts` | Captures + mixes mic and system audio via Web Audio |
| `src/wav.ts` | Resamples to 16 kHz mono WAV |
| `src/transcription.ts` | Spawns `whisper-cli`, reads the transcript |
| `src/settings.ts` | Settings tab |

## Scope & philosophy

The plugin deliberately stays **local-first and dependency-light**: no cloud calls,
no bundled binaries, no companion server. Features that require network access
should be opt-in and clearly disclosed. Keep the no-`ffmpeg`, no-server properties
intact unless there's a strong reason not to.

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).