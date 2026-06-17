# Using AI Meeting Notes

A step-by-step walkthrough from zero to your first transcribed meeting. If you
just want the reference tables, see the [README](../README.md). This guide
focuses on the part people actually get stuck on: **routing the meeting's audio
so it's both captured and audible.**

---

## The mental model

To transcribe a video call you need the plugin to hear two things at once:

- **Your microphone** - your voice.
- **The system audio** - everyone *else* on the call, i.e. whatever your Mac is
  playing through its speakers.

macOS doesn't let apps record system audio directly, so you install a virtual
"loopback" device (**BlackHole**) that the call's audio flows into. The plugin
records from BlackHole. The catch: if audio only goes to BlackHole, *you* can't
hear the call. The fix is a **Multi-Output Device** that sends sound to your
headphones **and** BlackHole at the same time.

```
                       ┌─► Headphones (you hear it)
Call audio ─► Multi-Output Device ┤
                       └─► BlackHole ─► AI Meeting Notes (records it)

Your voice ─► Microphone ─────────► AI Meeting Notes (records it)
```

You set this up **once**. After that, recording a meeting is two clicks.

---

## One-time setup

### 1. Install the tools

```bash
brew install blackhole-2ch whisper-cpp
mkdir -p ~/models
curl -L -o ~/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

### 2. Create the Multi-Output Device (so you can hear the call)

1. Open **Audio MIDI Setup** (Applications → Utilities, or Spotlight).
2. Click the **+** at the bottom-left → **Create Multi-Output Device**.
3. In the right panel, tick **both** your normal output (e.g. *MacBook Pro
   Speakers* or your headphones) **and** *BlackHole 2ch*.
4. Tip: put your real output device **first** in the list and enable **Drift
   Correction** on *BlackHole*.
5. Optionally rename it to something like *Meeting Output*.

You'll switch your Mac's output to this device during meetings (next section).

### 3. Configure the plugin in Obsidian

1. **Settings → Community plugins** → enable **AI Meeting Notes**.
2. Open **Settings → AI Meeting Notes** and:
   - Click **Grant** to allow microphone access (needed once so device names
     appear).
   - **Microphone** → your mic.
   - **System audio (loopback)** → *BlackHole 2ch*.
   - **Model path** → `~/models/ggml-base.en.bin`.
   - Leave the rest at defaults.

---

## Recording a meeting

1. **Before the call**, switch your Mac's sound output to your **Multi-Output
   Device**: System Settings → Sound → Output (or Option-click the menu-bar
   volume icon and pick it). You'll still hear everything normally.
2. When the meeting starts, click the **microphone icon** in the left ribbon
   (or run **Start meeting recording** from the command palette, Cmd-P). A 🔴
   indicator appears in the status bar.
3. Talk through your meeting as usual.
4. When it ends, click the ribbon icon again (or **Stop recording &
   transcribe**). You'll see a "Transcribing…" notice.
5. After a few moments a new note opens in your **Meetings** folder.

> Transcription happens **after** you stop - the whole recording is processed at
> once. On Apple Silicon a `base` model handles a 30-minute meeting in well under
> a minute. Larger models are slower but more accurate.

---

## What you get

A note named `Meeting YYYY-MM-DD HH-mm-ss.md` in your **Meetings** folder:

```markdown
---
type: meeting
date: 2026-06-17 14-30-00
---

# Meeting - 2026-06-17 14-30-00

## Transcript

Hello everyone, thanks for joining. Today we're going to cover...
```

If **Save audio file** is enabled (default), the recording is also kept at
`Meetings/recordings/Meeting <timestamp>.webm`. When both your mic and system
audio were captured, that file is **stereo**: your voice on the left channel,
the call on the right. Transcription mixes them down to mono automatically.

---

## Optional: AI summary & action items

The plugin can run each transcript through a **local** LLM to produce a summary
and an action-item checklist, prepended above the transcript in the note. This
is **off by default** and runs entirely on your machine via [Ollama](https://ollama.com).

1. Install Ollama and pull a model:
   ```bash
   brew install ollama
   ollama serve            # leave running (or it starts on login)
   ollama pull llama3.1    # or any model you like
   ```
2. In **Settings → AI Meeting Notes → AI summary**:
   - Turn on **Generate summary**.
   - Set **Ollama model** to the model you pulled (e.g. `llama3.1`).
   - Leave **Ollama URL** at `http://localhost:11434` unless you changed it.
   - Optionally tweak the **Summary prompt** (`{{transcript}}` is replaced with
     the transcript text).

Now when you stop a recording, the note will start with `## Summary`,
`## Key points`, and `## Action items` sections, followed by the full transcript.
If the summary step fails (e.g. Ollama isn't running), the transcript is still
saved - you just won't get a summary.

## Tips

- **Mic-only notes.** Leave **System audio** empty in settings to record just
  your microphone - handy for voice memos or in-person meetings where one mic
  hears the room.
- **Accuracy vs. speed.** `ggml-base.en.bin` is a good default. For tougher
  audio try `small.en` or `medium.en`; for non-English use a multilingual model
  (`ggml-small.bin`) and set **Language** accordingly (or leave it `auto`).
- **Keep the audio.** The saved stereo `.webm` lets you re-listen, and (later)
  enables speaker separation - leave **Save audio file** on if storage allows.
- **Forgot to switch output?** If your transcript only has your voice, your
  system output wasn't on the Multi-Output Device, or **System audio** wasn't
  selected in settings.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "whisper model not found" | Set **Model path** to the absolute path of your `.bin` (a leading `~` is expanded). |
| Device dropdowns are empty | Click **Grant** in settings, then reopen the settings tab. |
| Only my voice is transcribed | Output isn't on the Multi-Output Device, or **System audio** isn't selected. |
| I can't hear the meeting while recording | Your output is set to raw *BlackHole* instead of the **Multi-Output Device**. |
| Transcription is slow | Use a smaller model, or add threads. |
| Nothing happens / errors | Open the dev console (Cmd-Opt-I → Console); errors are tagged `[meeting-notes]`. |

---

## Privacy

Everything runs on your machine. By default the plugin makes no network requests
- audio is recorded, resampled, and transcribed locally by the `whisper.cpp`
binary and model you provide. The optional AI summary (off by default) sends the
transcript to a local Ollama instance on `localhost` and nowhere else. Nothing is
uploaded.