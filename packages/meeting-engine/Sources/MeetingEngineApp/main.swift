// MeetingEngineApp - a minimal AppKit GUI app whose only job (for now) is to be
// a *real, signed app* so macOS will present the system-audio-recording
// permission prompt - something a CLI cannot get. Clicking Record runs the same
// MeetingEngineCore capture used by the CLI.

import AppKit
import MeetingEngineCore

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var window: NSWindow!
	private let statusLabel = NSTextField(wrappingLabelWithString: "Ready. Click Record, then Allow the audio prompt if it appears.")
	private let recordButton = NSButton(title: "Record 10s (system + mic)", target: nil, action: nil)

	func applicationDidFinishLaunching(_ notification: Notification) {
		recordButton.target = self
		recordButton.action = #selector(record)
		statusLabel.preferredMaxLayoutWidth = 380

		let stack = NSStackView(views: [recordButton, statusLabel])
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
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered, defer: false)
		window.title = "Meeting Engine"
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
				let r = try MeetingEngine.record(seconds: 10, outBase: out, appName: nil) { msg in
					DispatchQueue.main.async { self.statusLabel.stringValue = msg }
				}
				DispatchQueue.main.async {
					self.statusLabel.stringValue = "Done. system: \(r.systemFrames) frames, mic: \(r.micFrames) frames. Files saved to ~/Desktop."
					self.recordButton.isEnabled = true
				}
			} catch {
				DispatchQueue.main.async {
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