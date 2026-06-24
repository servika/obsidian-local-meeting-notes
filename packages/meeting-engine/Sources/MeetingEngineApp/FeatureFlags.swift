import SwiftUI

/// Catalog of experimental / R&D feature flags.
///
/// A flag's stored on/off state lives in `AppSettings.featureFlags`, but a flag
/// only takes *effect* when the master `experimentalMode` switch is also on
/// (see `AppSettings.isEnabled`). Add a case here + its metadata to introduce a
/// new experiment; the Settings UI renders a toggle for every case automatically.
enum FeatureFlag: String, CaseIterable, Identifiable {
	/// Diarize the system track so remote participants become "Them 1 / Them 2 / …".
	case speakerRecognition

	var id: String { rawValue }

	/// UserDefaults key for the persisted on/off state.
	var storageKey: String { "ff.\(rawValue)" }

	/// Default state for users who have never toggled it.
	var defaultOn: Bool { false }

	/// Short label for the toggle.
	var title: String {
		switch self {
		case .speakerRecognition: return "Recognize speakers"
		}
	}

	/// One-paragraph explanation shown under the toggle.
	var details: String {
		switch self {
		case .speakerRecognition:
			return "Splits the remote side of the call into separate speakers (\"Them 1\", \"Them 2\", …) instead of one \"Them\", by analyzing the system-audio track. Your own mic is always \"You\". Accuracy varies with audio quality and overlapping speech, and it adds processing time."
		}
	}
}

extension AppSettings {
	/// Raw stored state of a flag, ignoring the master experimental switch.
	func flagValue(_ flag: FeatureFlag) -> Bool {
		featureFlags[flag.rawValue] ?? flag.defaultOn
	}

	/// Whether a flag's behavior should actually be active: its own state AND the
	/// master experimental switch.
	func isEnabled(_ flag: FeatureFlag) -> Bool {
		experimentalMode && flagValue(flag)
	}

	func setFlag(_ flag: FeatureFlag, _ on: Bool) {
		var f = featureFlags
		f[flag.rawValue] = on
		featureFlags = f
	}

	/// A two-way binding to a flag's raw state, for SwiftUI toggles.
	func flagBinding(_ flag: FeatureFlag) -> Binding<Bool> {
		Binding(get: { self.flagValue(flag) }, set: { self.setFlag(flag, $0) })
	}
}