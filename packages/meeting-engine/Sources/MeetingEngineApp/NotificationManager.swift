import AppKit
@preconcurrency import UserNotifications

/// Posts a native macOS notification when a meeting is detected, so the user is
/// alerted even when the app is in the background or hidden. The notification
/// carries a "Record" action that starts capture directly. Permission is
/// requested lazily on first use; delivery is gated to when the app isn't already
/// frontmost (the in-app nudge covers the foreground case).
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
	static let shared = NotificationManager()

	private let center = UNUserNotificationCenter.current()
	nonisolated private static let categoryID = "MEETING_DETECTED"
	nonisolated private static let recordActionID = "RECORD"

	/// Set by the app: what to do when the user taps "Record" on the notification.
	var onRecord: () -> Void = {}

	private var authorized = false

	/// Register the delegate + the "Record" action category. Call once at launch.
	func configure() {
		center.delegate = self
		let record = UNNotificationAction(identifier: Self.recordActionID, title: "Record",
			options: [.foreground])
		let category = UNNotificationCategory(identifier: Self.categoryID, actions: [record],
			intentIdentifiers: [], options: [])
		center.setNotificationCategories([category])
	}

	/// Notify that a meeting was detected. No-op if the app is already frontmost
	/// (the in-app nudge handles that). Requests permission on first use.
	func notifyMeetingDetected() {
		guard !NSApp.isActive else { return }
		ensureAuthorized { [weak self] granted in
			guard let self, granted else { return }
			let content = UNMutableNotificationContent()
			content.title = "Meeting detected"
			content.body = "Another app is using your microphone. Record this meeting?"
			content.categoryIdentifier = Self.categoryID
			content.sound = .default
			self.center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
		}
	}

	private func ensureAuthorized(_ completion: @escaping @MainActor (Bool) -> Void) {
		if authorized { completion(true); return }
		let center = self.center // UNUserNotificationCenter is Sendable; avoids main-actor capture
		center.getNotificationSettings { settings in
			switch settings.authorizationStatus {
			case .authorized, .provisional:
				Task { @MainActor in self.authorized = true; completion(true) }
			case .notDetermined:
				center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
					Task { @MainActor in self.authorized = granted; completion(granted) }
				}
			default:
				Task { @MainActor in completion(false) } // denied - respect the user's choice
			}
		}
	}

	// MARK: UNUserNotificationCenterDelegate

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void) {
		let id = response.actionIdentifier
		if id == Self.recordActionID || id == UNNotificationDefaultActionIdentifier {
			Task { @MainActor in self.onRecord() }
		}
		completionHandler()
	}

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		// Don't pop a banner over the app while it's frontmost.
		Task { @MainActor in completionHandler(NSApp.isActive ? [] : [.banner, .sound]) }
	}
}