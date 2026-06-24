namespace MeetingNotes.Core;

/// <summary>What to run after a recording stops, plus the inputs each stage needs.</summary>
public sealed record PipelineOptions
{
    public bool Transcribe { get; init; } = true;
    public bool Summarize { get; init; } = true;
    public string Language { get; init; } = "auto";
    public string WhisperModelPath { get; init; } = "";
    public string SummaryPrompt { get; init; } = "";
    public SummaryEngine? Engine { get; init; }
    public string AppVersion { get; init; } = "0.1.0";
}

/// <summary>
/// Headless processing pipeline: takes the two captured tracks and produces the
/// Obsidian note. Mirrors the macOS RecordingController stages - transcribe each
/// track (You = mic, Them = system), merge into a labeled transcript, summarize,
/// then write the note. Audio is always kept; transcription and summary are
/// gated by <see cref="PipelineOptions"/>.
/// </summary>
public sealed class MeetingPipeline(
    WhisperTranscriber transcriber, Summarizer summarizer, MeetingStore store)
{
    /// <summary>Process a finished recording into a note; returns the note's path.</summary>
    public async Task<string> ProcessAsync(
        string systemWav, string micWav, string title, DateTime date, string audioBase,
        int durationSeconds, int speakerCount, PipelineOptions opts, CancellationToken ct = default)
    {
        var transcript = "";
        var summary = "";

        if (opts.Transcribe)
        {
            var segments = new List<TranscriptSegment>();
            if (File.Exists(micWav))
                segments.AddRange(await transcriber.TranscribeAsync(micWav, opts.WhisperModelPath, "You", opts.Language, ct));
            if (File.Exists(systemWav))
                segments.AddRange(await transcriber.TranscribeAsync(systemWav, opts.WhisperModelPath, "Them", opts.Language, ct));
            transcript = Transcriber.DiarizedMarkdown(segments);

            if (opts.Summarize && opts.Engine is not null && transcript.Length > 0)
                summary = await summarizer.SummarizeAsync(transcript, opts.SummaryPrompt, opts.Engine, ct);
        }

        return store.WriteNote(
            title, date, audioBase, durationSeconds, speakerCount, summary, transcript, opts.AppVersion);
    }
}