using System.Globalization;
using System.Text;
using System.Text.Json;

namespace MeetingNotes.Core;

/// <summary>One transcribed span of speech, tagged with who spoke ("You"/"Them").</summary>
public readonly record struct TranscriptSegment(double Start, double End, string Text, string Speaker);

/// <summary>
/// Transcription + "You vs. Them" diarization. C# port of the macOS Transcriber
/// (packages/meeting-engine Transcriber.swift). The whisper.cpp invocation and
/// 16 kHz resampling are Windows-only (added in a later phase); the JSON parsing
/// and the timestamp-merge into a speaker-labeled transcript are pure and tested
/// here, kept identical to the macOS output so notes match across platforms.
/// </summary>
public static class Transcriber
{
    /// <summary>
    /// Parse whisper-cli `-oj` JSON output into segments tagged with
    /// <paramref name="speaker"/>. A silent track produces no/empty transcription
    /// - that's zero segments, not an error.
    /// </summary>
    public static List<TranscriptSegment> ParseSegments(string json, string speaker)
    {
        var segments = new List<TranscriptSegment>();
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("transcription", out var rawSegs) ||
            rawSegs.ValueKind != JsonValueKind.Array)
            return segments;

        foreach (var seg in rawSegs.EnumerateArray())
        {
            var text = (seg.TryGetProperty("text", out var t) ? t.GetString() ?? "" : "").Trim();
            if (text.Length == 0) continue;
            double from = 0, to = 0;
            if (seg.TryGetProperty("offsets", out var offsets))
            {
                from = NumberMs(offsets, "from");
                to = NumberMs(offsets, "to");
            }
            segments.Add(new TranscriptSegment(from / 1000, to / 1000, text, speaker));
        }
        return segments;
    }

    /// <summary>
    /// Merge segments from all speakers into a chronological, labeled transcript.
    /// Consecutive segments from the same speaker collapse into one line; long
    /// monologues break into paragraphs on a pause or a long, sentence-ending run.
    /// </summary>
    public static string DiarizedMarkdown(IEnumerable<TranscriptSegment> segments)
    {
        var sorted = segments.OrderBy(s => s.Start).ToList();
        var blocks = new List<string>();
        var speaker = "";
        var paragraph = new StringBuilder();
        var firstOfTurn = true;
        var lastEnd = 0.0;
        var paragraphStart = 0.0;

        void EndParagraph()
        {
            var trimmed = paragraph.ToString().Trim();
            if (trimmed.Length > 0)
            {
                var label = firstOfTurn ? $"**{speaker}:** " : "";
                blocks.Add($"[{Timestamp(paragraphStart)}] {label}{trimmed}");
                firstOfTurn = false;
            }
            paragraph.Clear();
        }

        foreach (var seg in sorted)
        {
            var text = seg.Text.Trim();
            if (text.Length == 0) continue;
            if (seg.Speaker != speaker)
            {
                EndParagraph();
                speaker = seg.Speaker;
                firstOfTurn = true;
            }
            else if (paragraph.Length > 0)
            {
                var gap = seg.Start - lastEnd;
                var p = paragraph.ToString();
                var endsSentence = p.EndsWith('.') || p.EndsWith('!') || p.EndsWith('?') || p.EndsWith('…');
                if (gap > 1.5 || (p.Length > 320 && endsSentence))
                    EndParagraph();
            }
            if (paragraph.Length == 0) paragraphStart = seg.Start;
            paragraph.Append(paragraph.Length == 0 ? "" : " ").Append(text);
            lastEnd = seg.End;
        }
        EndParagraph();
        return string.Join("\n\n", blocks);
    }

    /// <summary>Format seconds-from-start as <c>m:ss</c>, or <c>h:mm:ss</c> past an hour.</summary>
    internal static string Timestamp(double seconds)
    {
        var s = Math.Max(0, (int)Math.Round(seconds));
        int h = s / 3600, m = (s % 3600) / 60, sec = s % 60;
        return h > 0
            ? $"{h}:{m:D2}:{sec:D2}"
            : $"{m}:{sec:D2}";
    }

    private static double NumberMs(JsonElement parent, string key)
    {
        if (!parent.TryGetProperty(key, out var v)) return 0;
        return v.ValueKind switch
        {
            JsonValueKind.Number => v.GetDouble(),
            JsonValueKind.String when double.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d) => d,
            _ => 0,
        };
    }
}