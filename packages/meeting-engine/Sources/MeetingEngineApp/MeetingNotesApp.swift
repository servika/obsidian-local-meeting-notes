import SwiftUI

@main
struct MeetingNotesApp: App {
	@StateObject private var settings: AppSettings
	@StateObject private var store: MeetingStore
	@StateObject private var controller: RecordingController
	@StateObject private var detector: MeetingDetector

	init() {
		let s = AppSettings()
		let st = MeetingStore()
		let c = RecordingController(settings: s, store: st)
		let d = MeetingDetector()
		d.isBusy = { [weak c] in c?.isRecording == true || c?.busy == true }
		d.isEnabled = { [weak s] in s?.suggestOnMeetingDetected ?? true }
		_settings = StateObject(wrappedValue: s)
		_store = StateObject(wrappedValue: st)
		_controller = StateObject(wrappedValue: c)
		_detector = StateObject(wrappedValue: d)
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(settings)
				.environmentObject(store)
				.environmentObject(controller)
				.environmentObject(detector)
				.frame(minWidth: 760, minHeight: 480)
				.onAppear { detector.start() }
		}
		Settings {
			SettingsView().environmentObject(settings)
		}
	}
}