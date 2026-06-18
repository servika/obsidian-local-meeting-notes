import Foundation

struct Meeting: Identifiable, Hashable {
	let id: String
	let url: URL
	let title: String
	let modified: Date
	let durationSeconds: Int
	/// The app version that generated this note (empty for pre-versioning notes).
	let appVersion: String
}

/// Lists meeting notes (`*.md`) in the configured vault folder.
final class MeetingStore: ObservableObject {
	@Published var meetings: [Meeting] = []

	func reload(folder: URL?) {
		guard let folder = folder else { meetings = []; return }
		let fm = FileManager.default
		let items = (try? fm.contentsOfDirectory(
			at: folder,
			includingPropertiesForKeys: [.contentModificationDateKey],
			options: [.skipsHiddenFiles])) ?? []
		meetings = items
			.filter { $0.pathExtension.lowercased() == "md" }
			.map { url in
				let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
				let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
				let dur = Int(RecordingController.frontmatterValue("duration", in: content) ?? "") ?? 0
				let ver = RecordingController.frontmatterValue("app_version", in: content) ?? ""
				return Meeting(id: url.path, url: url, title: url.deletingPathExtension().lastPathComponent, modified: mod, durationSeconds: dur, appVersion: ver)
			}
			.sorted { $0.modified > $1.modified }
	}

	func content(of meeting: Meeting) -> String {
		(try? String(contentsOf: meeting.url, encoding: .utf8)) ?? ""
	}

	/// Rename a meeting note's file. Audio stays linked via the note's frontmatter.
	/// Returns the renamed Meeting (for reselection), or nil on no-op/failure.
	@discardableResult
	func rename(_ meeting: Meeting, to newName: String) -> Meeting? {
		let safe = newName
			.replacingOccurrences(of: "/", with: "-")
			.replacingOccurrences(of: ":", with: "-")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !safe.isEmpty, safe != meeting.title else { return nil }
		let dir = meeting.url.deletingLastPathComponent()
		let newURL = dir.appendingPathComponent(safe + ".md")
		guard !FileManager.default.fileExists(atPath: newURL.path) else { return nil }
		do { try FileManager.default.moveItem(at: meeting.url, to: newURL) } catch { return nil }
		reload(folder: dir)
		return meetings.first { $0.url == newURL }
	}

	/// Delete a meeting: the note and its linked audio tracks.
	func delete(_ meeting: Meeting) {
		let dir = meeting.url.deletingLastPathComponent()
		let content = (try? String(contentsOf: meeting.url, encoding: .utf8)) ?? ""
		let audioBase = RecordingController.frontmatterValue("audio", in: content) ?? "recordings/\(meeting.title)"
		try? FileManager.default.removeItem(at: meeting.url)
		for ext in ["system.wav", "mic.wav"] {
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(audioBase + "." + ext))
		}
		reload(folder: dir)
	}
}