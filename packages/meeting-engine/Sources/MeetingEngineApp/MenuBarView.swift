import SwiftUI
import AppKit

/// The menu-bar (status item) icon - reflects recording state at a glance.
struct MenuBarLabel: View {
	@ObservedObject var controller: RecordingController
	@ObservedObject var detector: MeetingDetector
	var body: some View {
		Image(systemName: iconName)
	}
	private var iconName: String {
		if controller.isRecording { return "record.circle.fill" }
		if controller.busy { return "hourglass" }
		if detector.suggestRecording { return "dot.radiowaves.left.and.right" }
		return "waveform"
	}
}

/// The menu shown when the status item is clicked: quick status + start/stop,
/// the meeting-detected nudge, open the window, and quit.
struct MenuBarContent: View {
	@ObservedObject var controller: RecordingController
	@ObservedObject var detector: MeetingDetector

	var body: some View {
		Text(statusText).font(.headline)

		if detector.suggestRecording && !controller.isRecording && !controller.busy {
			Button("Start Recording - meeting detected") {
				detector.clear()
				controller.start()
			}
		}

		Button(controller.isRecording ? "Stop & Transcribe" : "Start Recording") {
			controller.toggle()
		}
		.disabled(controller.busy)

		Divider()

		Button("Open AI Meeting Notes") { Self.activateApp() }
		Button("Quit") { NSApp.terminate(nil) }
	}

	private var statusText: String {
		if controller.isRecording { return "● Recording" }
		if controller.busy { return "Processing \(Int(controller.progress * 100))%" }
		if detector.suggestRecording { return "Meeting detected" }
		return "Ready"
	}

	/// Bring the app and its main window to the front.
	static func activateApp() {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
		for window in NSApp.windows where window.canBecomeMain {
			window.makeKeyAndOrderFront(nil)
		}
	}
}