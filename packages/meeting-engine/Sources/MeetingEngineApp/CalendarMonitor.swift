// Optional calendar signal for meeting detection.
//
// When the user opts in (Settings → Recording), we use EventKit to check whether
// a calendar event is happening right now. That lets the meeting-detected prompt
// fire only during real, scheduled meetings - cutting false "are you in a
// meeting?" nudges from any incidental mic use - and name the event in the card.
// Access is requested only when the feature is enabled, never at first launch.

import EventKit
import Foundation

final class CalendarMonitor {
	private let store = EKEventStore()
	private(set) var authorized = false

	/// Ask for calendar access (macOS 14+ full-access). Safe to call repeatedly;
	/// macOS only prompts once. Requires `NSCalendarsFullAccessUsageDescription`
	/// in the app's Info.plist.
	func requestAccess() {
		store.requestFullAccessToEvents { [weak self] granted, _ in
			DispatchQueue.main.async { self?.authorized = granted }
		}
	}

	/// Title of a timed (non-all-day, not cancelled) event happening at `now`, if
	/// any - nil when access isn't granted or nothing is on the calendar.
	func currentEventTitle(now: Date = Date()) -> String? {
		guard authorized else { return nil }
		let calendars = store.calendars(for: .event)
		guard !calendars.isEmpty else { return nil }
		// A ±30-min window is plenty to catch the event spanning "now".
		let predicate = store.predicateForEvents(
			withStart: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800), calendars: calendars)
		for event in store.events(matching: predicate)
		where !event.isAllDay && event.status != .canceled {
			if event.startDate <= now, event.endDate >= now {
				let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
				return title.isEmpty ? nil : title
			}
		}
		return nil
	}
}