using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using MeetingNotes.Audio;
using MeetingNotes.Core;

namespace MeetingNotes.App;

public partial class MainWindow : Window
{
    private static readonly string SettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "MeetingNotes", "settings.json");
    private const string AppVersion = "0.1.0";

    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromMinutes(5) };
    private MeetingRecorder? _recorder;
    private bool _recording;
    private string _audioBase = "";
    private string _outBase = "";
    private DateTime _recordStart;

    public MainWindow()
    {
        InitializeComponent();
        LoadSettings();
        RefreshMeetings();
    }

    private async void OnRecordClick(object sender, RoutedEventArgs e)
    {
        if (!_recording)
        {
            StartRecording();
            return;
        }
        await StopAndProcessAsync();
    }

    private void StartRecording()
    {
        var name = "Meeting " + DateTime.Now.ToString("yyyy-MM-dd HH-mm-ss");
        _recordStart = DateTime.Now;
        _audioBase = "recordings/" + name;
        _outBase = Path.Combine(VaultBox.Text, "recordings", name);
        Directory.CreateDirectory(Path.GetDirectoryName(_outBase)!);

        _recorder = new MeetingRecorder();
        _recorder.OnLevel += (sys, mic) => Dispatcher.Invoke(() =>
        {
            SystemLevel.Value = sys;
            MicLevel.Value = mic;
        });
        try
        {
            _recorder.Start(_outBase);
        }
        catch (Exception ex)
        {
            StatusText.Text = "Couldn't start recording: " + ex.Message;
            _recorder.Dispose();
            _recorder = null;
            return;
        }
        _recording = true;
        RecordButton.Content = "■ Stop & Process";
        StatusText.Text = "Recording…";
    }

    private async Task StopAndProcessAsync()
    {
        RecordButton.IsEnabled = false;
        StatusText.Text = "Stopping…";
        var result = await _recorder!.StopAsync();
        _recorder.Dispose();
        _recorder = null;
        _recording = false;
        SystemLevel.Value = MicLevel.Value = 0;
        RecordButton.Content = "● Record";

        var duration = (int)(DateTime.Now - _recordStart).TotalSeconds;
        var title = Path.GetFileName(_outBase);
        StatusText.Text = "Processing…";
        try
        {
            var store = new MeetingStore(VaultBox.Text);
            var pipeline = new MeetingPipeline(
                new WhisperTranscriber(WhisperBox.Text),
                new Summarizer(_http),
                store);
            var opts = new PipelineOptions
            {
                Transcribe = TranscribeCheck.IsChecked == true,
                Summarize = SummarizeCheck.IsChecked == true,
                Language = LanguageBox.Text,
                WhisperModelPath = ModelBox.Text,
                SummaryPrompt = SummaryPrompts.Default,
                Engine = BuildEngine(),
                AppVersion = AppVersion,
            };
            await Task.Run(() => pipeline.ProcessAsync(
                result.SystemPath, result.MicPath, title, _recordStart, _audioBase, duration, 0, opts));
            StatusText.Text = "Done.";
            RefreshMeetings();
        }
        catch (Exception ex)
        {
            StatusText.Text = "Processing failed: " + ex.Message;
        }
        finally
        {
            RecordButton.IsEnabled = true;
        }
    }

    private SummaryEngine? BuildEngine() => (EngineBox.SelectedItem as ComboBoxItem)?.Content switch
    {
        "Ollama" => new SummaryEngine.Ollama(OllamaUrlBox.Text, OllamaModelBox.Text),
        "Claude" => new SummaryEngine.Claude(ClaudeKeyBox.Password, ClaudeModelBox.Text),
        _ => null,
    };

    private void RefreshMeetings()
    {
        if (string.IsNullOrWhiteSpace(VaultBox.Text)) return;
        MeetingList.ItemsSource = new MeetingStore(VaultBox.Text).List();
    }

    private void OnMeetingSelected(object sender, SelectionChangedEventArgs e)
    {
        if (MeetingList.SelectedItem is Meeting m && File.Exists(m.Path))
            DetailBox.Text = File.ReadAllText(m.Path);
    }

    // ---- settings persistence ----

    private sealed record Settings(
        string Vault = "", string Model = "", string Whisper = "", string Language = "auto",
        int Engine = 0, string OllamaUrl = "http://localhost:11434", string OllamaModel = "qwen2.5:7b",
        string ClaudeModel = "claude-opus-4-8");

    private void OnSaveSettings(object sender, RoutedEventArgs e)
    {
        var s = new Settings(
            VaultBox.Text, ModelBox.Text, WhisperBox.Text, LanguageBox.Text,
            EngineBox.SelectedIndex, OllamaUrlBox.Text, OllamaModelBox.Text, ClaudeModelBox.Text);
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(s));
        StatusText.Text = "Settings saved.";
        RefreshMeetings();
    }

    private void LoadSettings()
    {
        if (!File.Exists(SettingsPath)) return;
        var s = JsonSerializer.Deserialize<Settings>(File.ReadAllText(SettingsPath));
        if (s is null) return;
        VaultBox.Text = s.Vault;
        ModelBox.Text = s.Model;
        WhisperBox.Text = s.Whisper;
        LanguageBox.Text = s.Language;
        EngineBox.SelectedIndex = s.Engine;
        OllamaUrlBox.Text = s.OllamaUrl;
        OllamaModelBox.Text = s.OllamaModel;
        ClaudeModelBox.Text = s.ClaudeModel;
    }
}