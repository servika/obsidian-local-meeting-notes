// MeetingEngineApp - a minimal AppKit GUI app whose job is to be a *real, signed
// app* so macOS will present the system-audio-recording permission prompt (a CLI
// cannot get it). Clicking Record runs MeetingEngineCore's capture and shows live
// System / Mic level meters so you can confirm both sources are picking up audio.

import AppKit
import AVFoundation
import MeetingEngineCore

private func makeMeter() -> NSLevelIndicator {
	let m = NSLevelIndicator()
	m.levelIndicatorStyle = .continuousCapacity
	m.minValue = 0
	m.maxValue = 1
	m.warningValue = 0.85
	m.criticalValue = 0.97
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
	private let statusLabel = NSTextField(wrappingLabelWithString: "Ready. Click Record, then Allow the prompts. The bars show live input levels.")
	private let recordButton = NSButton(title: "Record 10s (system + mic)", target: nil, action: nil)
	private let systemMeter = makeMeter()
	private let micMeter = makeMeter()

	func applicationDidFinishLaunching(_ notification: Notification) {
		recordButton.target = self
		recordButton.action = #selector(record)
		statusLabel.preferredMaxLayoutWidth = 360

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
			contentRect: NSRect(x: 0, y: 0, width: 380, height: 210),
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered, defer: false)
		window.title = "AI Meeting Notes"
		window.contentView = content
		window.center()
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	@objc private func record() {
		recordButton.isEnabled = false
		statusLabel.stringValue = "Recording 10s… play some audio and talk."
		let out = "~/Desktop/meeting-engine-app"
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				let r = try MeetingEngine.record(
					seconds: 10,
					outBase: out,
					appName: nil,
					onLevel: { [weak self] sys, mic in
						DispatchQueue.main.async {
							self?.systemMeter.doubleValue = Double(sys)
							self?.micMeter.doubleValue = Double(mic)
						}
					},
					log: { [weak self] msg in
						DispatchQueue.main.async { self?.statusLabel.stringValue = msg }
					})
				DispatchQueue.main.async {
					self.systemMeter.doubleValue = 0
					self.micMeter.doubleValue = 0
					let micNote = r.micFrames > 0 ? "" : "  ⚠️ mic empty - check Microphone permission"
					self.statusLabel.stringValue = "Done. system: \(r.systemFrames) frames, mic: \(r.micFrames) frames.\(micNote)\nFiles saved to ~/Desktop."
					self.recordButton.isEnabled = true
				}
			} catch {
				DispatchQueue.main.async {
					self.systemMeter.doubleValue = 0
					self.micMeter.doubleValue = 0
					self.statusLabel.stringValue = "Error: \(error)"
					self.recordButton.isEnabled = true
				}
			}
		}
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()