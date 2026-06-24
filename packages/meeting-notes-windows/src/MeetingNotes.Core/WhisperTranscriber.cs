using System.Diagnostics;

namespace MeetingNotes.Core;

/// <summary>
/// Runs the bundled whisper.cpp CLI (`whisper-cli.exe`) on a 16 kHz mono WAV and
/// parses its `-oj` JSON into tagged segments. The capture step already produces
/// 16 kHz mono tracks, so no resampling is needed here. Process invocation is
/// cross-platform; only the bundled binary is Windows-specific.
/// </summary>
public sealed class WhisperTranscriber(string whisperExePath)
{
    /// <summary>
    /// Transcribe one WAV, tagging every segment with <paramref name="speaker"/>.
    /// A silent track yields zero segments rather than an error.
    /// </summary>
    public async Task<List<TranscriptSegment>> TranscribeAsync(
        string wavPath, string modelPath, string speaker,
        string language = "auto", CancellationToken ct = default)
    {
        if (!File.Exists(modelPath))
            throw new InvalidOperationException($"whisper model not found: {modelPath}");

        var outBase = Path.Combine(
            Path.GetDirectoryName(wavPath)!, Path.GetFileNameWithoutExtension(wavPath));
        var jsonPath = outBase + ".json";

        var args = new[]
        {
            "-m", modelPath, "-f", wavPath, "-l", language,
            "-oj", "-of", outBase, "--suppress-nst",
        };
        await RunAsync(whisperExePath, args, ct);

        if (!File.Exists(jsonPath)) return []; // no speech detected
        return Transcriber.ParseSegments(await File.ReadAllTextAsync(jsonPath, ct), speaker);
    }

    private static async Task RunAsync(string exe, IReadOnlyList<string> args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var proc = new Process { StartInfo = psi };
        proc.Start();
        var stderr = await proc.StandardError.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);
        if (proc.ExitCode != 0)
        {
            var tail = stderr.Length > 400 ? stderr[^400..] : stderr;
            throw new InvalidOperationException($"whisper-cli exited {proc.ExitCode}: {tail}");
        }
    }
}