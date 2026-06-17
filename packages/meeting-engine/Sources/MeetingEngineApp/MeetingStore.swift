import Foundation

struct Meeting: Identifiable, Hashable {
	let id: String
	let url: URL
	let title: String
	let modified: Date
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
				return Meeting(id: url.path, url: url, title: url.deletingPathExtension().lastPathComponent, modified: mod)
			}
			.sorted { $0.modified > $1.modified }
	}

	func content(of meeting: Meeting) -> String {
		(try? String(contentsOf: meeting.url, encoding: .utf8)) ?? ""
	}
}