import SwiftUI

@main
struct MeetingNotesApp: App {
	@StateObject private var settings: AppSettings
	@StateObject private var store: MeetingStore
	@StateObject private var controller: RecordingController

	init() {
		let s = AppSettings()
		let st = MeetingStore()
		_settings = StateObject(wrappedValue: s)
		_store = StateObject(wrappedValue: st)
		_controller = StateObject(wrappedValue: RecordingController(settings: s, store: st))
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(settings)
				.environmentObject(store)
				.environmentObject(controller)
				.frame(minWidth: 760, minHeight: 480)
		}
		Settings {
			SettingsView().environmentObject(settings)
		}
	}
}