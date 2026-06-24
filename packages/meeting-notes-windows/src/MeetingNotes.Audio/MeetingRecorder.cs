using NAudio.CoreAudioApi;
using NAudio.MediaFoundation;
using NAudio.Wave;

namespace MeetingNotes.Audio;

/// <summary>Paths + frame counts for a finished recording's two tracks.</summary>
public readonly record struct CaptureResult(string SystemPath, string MicPath, long SystemFrames, long MicFrames);

/// <summary>
/// Captures the meeting as two separate WAV tracks with zero setup:
/// system audio via WASAPI loopback on the default render endpoint, and the mic
/// via WASAPI capture on the default capture endpoint. This is the Windows
/// equivalent of the macOS Core Audio process taps - no virtual audio device.
///
/// Each track is captured at its device format, then resampled to whisper's
/// required 16 kHz mono 16-bit PCM on Stop(). Subscribe to <see cref="OnLevel"/>
/// for live (system, mic) peak levels in 0…1 to drive VU meters.
/// </summary>
public sealed class MeetingRecorder : IDisposable
{
    // whisper.cpp wants 16 kHz mono 16-bit PCM.
    private static readonly WaveFormat WhisperFormat = new(16000, 16, 1);

    private WasapiLoopbackCapture? _system;
    private WasapiCapture? _mic;
    private WaveFileWriter? _systemWriter;
    private WaveFileWriter? _micWriter;
    private string _systemTemp = "";
    private string _micTemp = "";
    private string _outBase = "";
    private float _systemLevel;
    private float _micLevel;

    /// <summary>Fired per buffer with the latest peak levels (0…1) for (system, mic).</summary>
    public event Action<float, float>? OnLevel;

    /// <summary>Begin capturing to temp files; the final tracks are written on <see cref="StopAsync"/>.</summary>
    public void Start(string outBase)
    {
        _outBase = outBase;
        _systemTemp = Path.GetTempFileName();
        _micTemp = Path.GetTempFileName();

        // System (loopback). Constructing throws if there's no default render device.
        _system = new WasapiLoopbackCapture();
        _systemWriter = new WaveFileWriter(_systemTemp, _system.WaveFormat);
        _system.DataAvailable += (_, e) =>
        {
            _systemWriter!.Write(e.Buffer, 0, e.BytesRecorded);
            _systemLevel = PeakLevel(e.Buffer, e.BytesRecorded, _system!.WaveFormat);
            OnLevel?.Invoke(_systemLevel, _micLevel);
        };

        // Mic (default capture endpoint).
        _mic = new WasapiCapture();
        _micWriter = new WaveFileWriter(_micTemp, _mic.WaveFormat);
        _mic.DataAvailable += (_, e) =>
        {
            _micWriter!.Write(e.Buffer, 0, e.BytesRecorded);
            _micLevel = PeakLevel(e.Buffer, e.BytesRecorded, _mic!.WaveFormat);
            OnLevel?.Invoke(_systemLevel, _micLevel);
        };

        _system.StartRecording();
        _mic.StartRecording();
    }

    /// <summary>Stop both captures and write the resampled 16 kHz mono tracks.</summary>
    public async Task<CaptureResult> StopAsync()
    {
        await StopAndFlushAsync(_system, () => { _systemWriter?.Dispose(); _systemWriter = null; });
        await StopAndFlushAsync(_mic, () => { _micWriter?.Dispose(); _micWriter = null; });

        var systemOut = _outBase + ".system.wav";
        var micOut = _outBase + ".mic.wav";
        var systemFrames = Resample(_systemTemp, systemOut);
        var micFrames = Resample(_micTemp, micOut);

        TryDelete(_systemTemp);
        TryDelete(_micTemp);
        return new CaptureResult(systemOut, micOut, systemFrames, micFrames);
    }

    private static async Task StopAndFlushAsync(IWaveIn? capture, Action disposeWriter)
    {
        if (capture is null) return;
        var tcs = new TaskCompletionSource();
        void Stopped(object? s, StoppedEventArgs e) => tcs.TrySetResult();
        capture.RecordingStopped += Stopped;
        capture.StopRecording();
        await tcs.Task;
        capture.RecordingStopped -= Stopped;
        disposeWriter();
        capture.Dispose();
    }

    /// <summary>Resample a captured temp WAV to 16 kHz mono 16-bit; returns frame count.</summary>
    private static long Resample(string src, string dst)
    {
        if (!File.Exists(src) || new FileInfo(src).Length == 0) return 0;
        MediaFoundationApi.Startup();
        using var reader = new WaveFileReader(src);
        using var resampler = new MediaFoundationResampler(reader, WhisperFormat) { ResamplerQuality = 60 };
        WaveFileWriter.CreateWaveFile(dst, resampler);
        using var outReader = new WaveFileReader(dst);
        return outReader.SampleCount;
    }

    /// <summary>Peak amplitude (0…1) of a capture buffer, for VU metering.</summary>
    private static float PeakLevel(byte[] buffer, int bytes, WaveFormat format)
    {
        float peak = 0;
        if (format.Encoding == WaveFormatEncoding.IeeeFloat && format.BitsPerSample == 32)
        {
            for (var i = 0; i + 4 <= bytes; i += 4)
            {
                var sample = Math.Abs(BitConverter.ToSingle(buffer, i));
                if (sample > peak) peak = sample;
            }
        }
        else if (format.BitsPerSample == 16)
        {
            for (var i = 0; i + 2 <= bytes; i += 2)
            {
                var sample = Math.Abs(BitConverter.ToInt16(buffer, i) / 32768f);
                if (sample > peak) peak = sample;
            }
        }
        return Math.Clamp(peak, 0f, 1f);
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best effort */ }
    }

    public void Dispose()
    {
        _systemWriter?.Dispose();
        _micWriter?.Dispose();
        _system?.Dispose();
        _mic?.Dispose();
    }
}