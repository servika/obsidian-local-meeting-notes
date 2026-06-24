namespace MeetingNotes.Core;

/// <summary>
/// Builds and parses the Obsidian Markdown note for a meeting. The format is kept
/// byte-for-byte compatible with the macOS app (packages/meeting-engine
/// RecordingController.buildNote / frontmatterValue) so notes are interchangeable
/// across platforms.
/// </summary>
public static class NoteFormat
{
    /// <summary>
    /// Build the full note Markdown. <paramref name="audioBase"/> is the
    /// vault-relative recording path stem, e.g. "recordings/Meeting 2026-06-24".
    /// </summary>
    public static string BuildNote(
        string title,
        string date,
        string audioBase,
        int durationSeconds,
        int speakerCount,
        string summary,
        string transcript,
        string appVersion)
    {
        var audioName = LastPathComponent(audioBase);

        var s = "---\ntype: meeting\ntags: [meeting]\ndate: " + date + "\naudio: " + audioBase + "\n";
        if (durationSeconds > 0) s += "duration: " + durationSeconds + "\n";
        if (speakerCount >= 2) s += "speakers: " + speakerCount + "\n";
        s += "app_version: " + appVersion + "\n";
        s += "---\n\n# " + title + "\n\n";
        if (!string.IsNullOrEmpty(summary)) s += summary + "\n\n";
        s += "## Transcript\n\n" + (string.IsNullOrEmpty(transcript) ? "_(no speech detected)_" : transcript) + "\n";
        // Embed the audio so Obsidian shows inline players. The app hides this
        // section (it has its own access to the recordings).
        s += "\n## Audio\n\n**You (microphone)**\n\n![[" + audioName + ".mic.wav]]\n\n";
        s += "**Them (system audio)**\n\n![[" + audioName + ".system.wav]]\n";
        return s;
    }

    /// <summary>
    /// Read a <c>key: value</c> line from a note's YAML frontmatter block, or null
    /// if the content has no frontmatter or the key is absent.
    /// </summary>
    public static string? FrontmatterValue(string key, string content)
    {
        if (!content.StartsWith("---", StringComparison.Ordinal)) return null;
        var prefix = key + ":";
        var inBlock = false;
        var lines = content.Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (i == 0 && line == "---") { inBlock = true; continue; }
            if (inBlock && line == "---") break;
            if (inBlock && line.StartsWith(prefix, StringComparison.Ordinal))
                return line.Substring(prefix.Length).Trim();
        }
        return null;
    }

    /// <summary>Last path component of a "/"-separated stem (no OS path rules).</summary>
    private static string LastPathComponent(string path)
    {
        var idx = path.LastIndexOf('/');
        return idx < 0 ? path : path[(idx + 1)..];
    }
}