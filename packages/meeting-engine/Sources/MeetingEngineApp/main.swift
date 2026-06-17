// MeetingEngineApp - record a meeting (system + mic, no BlackHole), then
// auto-transcribe into a diarized You/Them note. Start/Stop controlled; live
// level meters confirm both sources are picking up audio.

import AppKit
import AVFoundation
import MeetingEngineCore

private let kModelPath = "~/models/ggml-base.en.bin"
private let kOutBase = "~/Desktop/meeting-engine-app"

private func makeMeter() -> NSLevelIndicator {
	let m = NSLevelIndicator()
	m.levelIndicatorStyle = .continuousCapacity
	m.minValue = 0; m.maxValue = 1
	m.warningValue = 0.85; m.criticalValue = 0.97
	m.doubleValue = 0
	m.translatesAutoresizingMaskIntoConstraints = false
	m.widthAnchor.constraint(equalToConstant: 260).isActive = true
	m.heightAnchor.constraint(equalToConstant: 18).isActive = true
	return m
}

private func meterRow(_ title: String, _ meter: NSLevelIndicator) -> NSStackView {
	let label = NSTextField(labelWithString: title)
	label.translatesAutoresizingMaskIntoConstraints = false
	label.widthAnchor.constraint(equalToConstant: 56).isActive = true
	let row = NSStackView(views: [label, meter])
	row.orientation = .horizontal
	row.spacing = 8
	row.alignment = .centerY
	return row
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var window: NSWindow!
	private let statusLabel = NSTextField(wrappingLabelWithString: "Ready. Click Record, then Allow the prompts. Click Stop to transcribe.")
	private let recordButton = NSButton(title: "Record", target: nil, action: nil)
	private let systemMeter = makeMeter()
	private let micMeter = makeMeter()
	private var recorder: MeetingRecorder?

	func applicationDidFinishLaunching(_ notification: Notification) {
		recordButton.target = self
		recordButton.action = #selector(toggle)
		recordButton.keyEquivalent = "\r"
		statusLabel.preferredMaxLayoutWidth = 380

		let stack = NSStackView(views: [
			recordButton,
			meterRow("System", systemMeter),
			meterRow("Mic", micMeter),
			statusLabel,
		])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 12
		stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
		stack.translatesAutoresizingMaskIntoConstraints = false

		let content = NSView()
		content.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			stack.topAnchor.constraint(equalTo: content.topAnchor),
			stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])

		window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 210),
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered, defer: false)
		window.title = "AI Meeting Notes"
		window.contentView = content
		window.center()
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	@objc private func toggle() {
		if recorder?.isRecording == true {
			stopAndTranscribe()
		} else {
			startRecording()
		}
	}

	private func setStatus(_ s: String) { DispatchQueue.main.async { self.statusLabel.stringValue = s } }

	private func startRecording() {
		let r = MeetingRecorder(log: { [weak self] msg in self?.setStatus(msg) })
		r.onLevel = { [weak self] sys, mic in
			DispatchQueue.main.async {
				self?.systemMeter.doubleValue = Double(sys)
				self?.micMeter.doubleValue = Double(mic)
			}
		}
		do {
			try r.start(outBase: (kOutBase as NSString).expandingTildeInPath, appName: nil)
			recorder = r
			recordButton.title = "Stop & Transcribe"
			statusLabel.stringValue = "Recording… click Stop when the meeting ends."
		} catch {
			statusLabel.stringValue = "Couldn't start: \(error)"
		}
	}

	private func stopAndTranscribe() {
		guard let r = recorder else { return }
		recordButton.isEnabled = false
		statusLabel.stringValue = "Finishing recording…"
		DispatchQueue.global(qos: .userInitiated).async {
			let result = r.stop()
			DispatchQueue.main.async {
				self.systemMeter.doubleValue = 0
				self.micMeter.doubleValue = 0
				self.recorder = nil
				self.recordButton.title = "Record"
				self.statusLabel.stringValue = "Transcribing… (system \(result.systemFrames), mic \(result.micFrames) frames)"
			}
			self.transcribe(result)
		}
	}

	private func transcribe(_ result: CaptureResult) {
		let model = (kModelPath as NSString).expandingTildeInPath
		do {
			let them = try Transcriber.transcribe(wavPath: result.systemURL.path, model: model, speaker: "Them", log: { [weak self] in self?.setStatus($0) })
			let you = try Transcriber.transcribe(wavPath: result.micURL.path, model: model, speaker: "You", log: { [weak self] in self?.setStatus($0) })
			let transcript = Transcriber.diarizedMarkdown(them + you)

			let stamp = Self.timestamp()
			let notePath = (("~/Desktop/Meeting \(stamp).md") as NSString).expandingTildeInPath
			let body = "# Meeting \(stamp)\n\n" + (transcript.isEmpty ? "_(no speech detected)_" : transcript) + "\n"
			try body.write(toFile: notePath, atomically: true, encoding: .utf8)

			DispatchQueue.main.async {
				self.statusLabel.stringValue = "✅ Saved: \(notePath)"
				NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: notePath)])
				self.recordButton.isEnabled = true
			}
		} catch {
			DispatchQueue.main.async {
				self.statusLabel.stringValue = "Transcription failed: \(error)"
				self.recordButton.isEnabled = true
			}
		}
	}

	private static func timestamp() -> String {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd HH-mm-ss"
		return f.string(from: Date())
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()