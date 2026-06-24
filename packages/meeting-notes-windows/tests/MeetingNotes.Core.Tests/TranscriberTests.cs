using MeetingNotes.Core;

namespace MeetingNotes.Core.Tests;

public class TranscriberTests
{
    [Fact]
    public void ParseSegments_reads_text_and_offsets()
    {
        const string json = """
        {"transcription":[
          {"text":" Hello there","offsets":{"from":1000,"to":2500}},
          {"text":"  ","offsets":{"from":2500,"to":3000}},
          {"text":"second","offsets":{"from":3000,"to":4000}}
        ]}
        """;
        var segs = Transcriber.ParseSegments(json, "You");
        Assert.Equal(2, segs.Count); // blank-text segment dropped
        Assert.Equal("Hello there", segs[0].Text);
        Assert.Equal(1.0, segs[0].Start);
        Assert.Equal(2.5, segs[0].End);
        Assert.Equal("You", segs[0].Speaker);
    }

    [Fact]
    public void ParseSegments_handles_missing_transcription_as_empty()
    {
        Assert.Empty(Transcriber.ParseSegments("{}", "Them"));
    }

    [Fact]
    public void DiarizedMarkdown_labels_turns_and_sorts_by_time()
    {
        var segs = new[]
        {
            new TranscriptSegment(0.0, 1.0, "Hi", "You"),
            new TranscriptSegment(2.0, 3.0, "Hello back", "Them"),
            new TranscriptSegment(1.0, 1.5, "there", "You"),
        };
        var md = Transcriber.DiarizedMarkdown(segs);
        var expected =
            "[0:00] **You:** Hi there\n\n" +
            "[0:02] **Them:** Hello back";
        Assert.Equal(expected, md);
    }

    [Fact]
    public void DiarizedMarkdown_breaks_paragraph_on_long_pause()
    {
        var segs = new[]
        {
            new TranscriptSegment(0.0, 1.0, "First part", "You"),
            new TranscriptSegment(5.0, 6.0, "after a gap", "You"), // gap > 1.5s
        };
        var md = Transcriber.DiarizedMarkdown(segs);
        // Same speaker, but the pause splits into two lines; only the first is labeled.
        Assert.Equal("[0:00] **You:** First part\n\n[0:05] after a gap", md);
    }

    [Theory]
    [InlineData(0, "0:00")]
    [InlineData(65, "1:05")]
    [InlineData(3661, "1:01:01")]
    public void Timestamp_formats(double seconds, string expected)
    {
        Assert.Equal(expected, Transcriber.Timestamp(seconds));
    }
}