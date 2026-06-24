# Open-source credits & licenses

AI Meeting Notes is built on excellent open-source software. This page lists what
powers the app and the licenses behind each part, so you know exactly what's
running on your machine.

The app itself is free and open source under the **MIT license**
([LICENSE](LICENSE)). Everything below runs **locally** unless you choose the
Claude cloud option for summaries.

## What's inside

| What it does | Project | License |
|---|---|---|
| Turns speech into text | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) + OpenAI Whisper models | MIT |
| Skips silent parts | [Silero VAD](https://github.com/snakers4/silero-vad) | MIT |
| Records your audio (Windows) | [NAudio](https://github.com/naudio/NAudio) | MIT |
| Runs the Windows app | [.NET](https://github.com/dotnet/runtime) | MIT |
| Local AI summaries (optional) | [Ollama](https://github.com/ollama/ollama) + the model you choose | MIT (Ollama); model licenses vary |
| Cloud AI summaries (optional) | [Anthropic Claude API](https://www.anthropic.com) | Anthropic's terms, with your own key |
| Recognizes different speakers (macOS, experimental) | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + speaker models | Apache-2.0 / MIT |

All of these are permissively licensed, so they ship inside the app with their
credits preserved - nothing here limits how you use AI Meeting Notes.

## A note on the optional pieces

- **AI summaries are optional.** Transcription happens fully on your device. You
  only get summaries if you turn them on - either with **Ollama** (a separate
  local app you install, also free and open source) or the **Claude API** (the one
  case where transcript text is sent to a cloud service, using your own API key).
- **The summary model is your choice.** When you use Ollama you pick which model
  to download, and each model comes with its own license - most defaults (like
  Qwen2.5) are permissive, while a few (like Meta's Llama) have extra usage terms.
  The app suggests a permissive default; which model you run, and under what terms,
  is up to you.
- **BlackHole (Obsidian plugin only).** The macOS and Windows apps capture system
  audio with no extra setup. The older Obsidian-plugin route instead asks you to
  install [BlackHole](https://github.com/ExistentialAudio/BlackHole), a free
  loopback audio driver. It's licensed GPL-3.0 and you install it yourself - it is
  never bundled into the app.

## Your privacy

Recording, transcription, and (with Ollama) summarizing all happen on your
computer. The only time anything leaves your machine is if you deliberately choose
the Claude summary option, which sends the transcript text to Anthropic. A
local-only setup makes no network requests except when you ask it to download a
model.

---

*Licenses are summarized here for convenience and reflect the versions the app
ships. Each linked project carries the authoritative license text.*