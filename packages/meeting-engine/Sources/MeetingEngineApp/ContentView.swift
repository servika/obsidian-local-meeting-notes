import SwiftUI
import AppKit

let brand = Color(red: 0.36, green: 0.30, blue: 0.92)

struct ContentView: View {
	@EnvironmentObject var settings: AppSettings
	@EnvironmentObject var store: MeetingStore
	@EnvironmentObject var controller: RecordingController
	@State private var selection: Meeting.ID?

	var body: some View {
		NavigationSplitView {
			VStack(spacing: 0) {
				List(store.meetings, selection: $selection) { meeting in
					MeetingRow(meeting: meeting)
						.contextMenu {
							Button("Delete", role: .destructive) {
								store.delete(meeting)
								if selection == meeting.id { selection = nil }
							}
						}
				}
				.listStyle(.sidebar)

				Divider()
				RecordPanel().environmentObject(controller).padding(14)
			}
			.navigationSplitViewColumnWidth(min: 250, ideal: 290)
		} detail: {
			if let id = selection, let meeting = store.meetings.first(where: { $0.id == id }) {
				MeetingDetail(
					meeting: meeting,
					content: store.content(of: meeting),
					busy: controller.busy,
					progress: controller.progress,
					status: controller.status,
					onRename: { newName in
						if let renamed = store.rename(meeting, to: newName) { selection = renamed.id }
					},
					onRegenerate: { controller.regenerate(meeting) },
					onDelete: { store.delete(meeting); selection = nil },
					onCancel: { controller.cancelProcessing() })
			} else {
				ContentUnavailableView("No meeting selected", systemImage: "waveform",
					description: Text("Record a meeting, or pick one from the list."))
			}
		}
		.tint(brand)
		.onAppear { store.reload(folder: settings.meetingsDirURL) }
		.onChange(of: controller.justCreatedID) {
			if let id = controller.justCreatedID { selection = id }
		}
	}
}

struct MeetingRow: View {
	let meeting: Meeting
	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "waveform.circle.fill")
				.font(.title2)
				.foregroundStyle(brand)
			VStack(alignment: .leading, spacing: 1) {
				Text(meeting.title).lineLimit(1)
				Text(meeting.modified, format: .dateTime.month().day().hour().minute())
					.font(.caption).foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 2)
	}
}

struct RecordPanel: View {
	@EnvironmentObject var controller: RecordingController
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Button(action: { controller.toggle() }) {
				Label(controller.isRecording ? "Stop & Transcribe" : "Record",
					systemImage: controller.isRecording ? "stop.fill" : "record.circle")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.tint(controller.isRecording ? .red : brand)
			.disabled(controller.busy)

			if controller.busy {
				ProgressView(value: controller.progress).progressViewStyle(.linear)
				HStack {
					Text("\(Int(controller.progress * 100))%")
					Spacer()
					Text(controller.elapsed)
				}
				.font(.caption).foregroundStyle(.secondary)
				Button("Stop processing", role: .destructive) { controller.cancelProcessing() }
					.controlSize(.small)
			} else {
				LevelBar(label: "System", level: controller.systemLevel)
				LevelBar(label: "Mic", level: controller.micLevel)
			}

			Text(controller.status)
				.font(.caption).foregroundStyle(.secondary)
				.lineLimit(3).fixedSize(horizontal: false, vertical: true)
		}
	}
}

struct LevelBar: View {
	let label: String
	let level: Float
	var body: some View {
		HStack(spacing: 8) {
			Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					Capsule().fill(Color.secondary.opacity(0.15))
					Capsule().fill(brand.opacity(0.8))
						.frame(width: max(2, geo.size.width * CGFloat(min(max(level, 0), 1))))
				}
			}
			.frame(height: 6)
		}
	}
}

struct MeetingDetail: View {
	let meeting: Meeting
	let content: String
	let busy: Bool
	let progress: Double
	let status: String
	let onRename: (String) -> Void
	let onRegenerate: () -> Void
	let onDelete: () -> Void
	let onCancel: () -> Void
	@State private var titleField = ""
	@State private var confirmingDelete = false
	@State private var copied = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 8) {
				TextField("Title", text: $titleField)
					.textFieldStyle(.plain)
					.font(.title2.weight(.semibold))
					.onSubmit { onRename(titleField) }
				Spacer()
				Button {
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(content, forType: .string)
					copied = true
					DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
				} label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
					.help("Copy full note as Markdown")
				Button { onRename(titleField) } label: { Image(systemName: "pencil") }
					.help("Rename")
					.disabled(titleField.trimmingCharacters(in: .whitespaces).isEmpty || titleField == meeting.title)
				Button { onRegenerate() } label: { Image(systemName: "arrow.clockwise") }
					.help("Re-transcribe & summarize")
					.disabled(busy)
				Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }
					.help("Delete meeting")
					.disabled(busy)
			}
			.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
			.confirmationDialog("Delete “\(meeting.title)”?", isPresented: $confirmingDelete) {
				Button("Delete meeting & recording", role: .destructive, action: onDelete)
				Button("Cancel", role: .cancel) {}
			} message: {
				Text("This removes the note and its audio recordings. This can't be undone.")
			}

			if busy {
				HStack(spacing: 12) {
					VStack(alignment: .leading, spacing: 4) {
						ProgressView(value: progress).progressViewStyle(.linear)
						Text(status).font(.caption).foregroundStyle(.secondary)
					}
					Button("Stop", role: .destructive) { onCancel() }
						.controlSize(.small)
				}
				.padding(.horizontal, 20).padding(.bottom, 10)
			}

			Divider()

			TabView {
				ScrollView {
					NoteView(markdown: content, only: .summary)
						.frame(maxWidth: .infinity, alignment: .leading).padding(20)
				}
				.tabItem { Label("Summary", systemImage: "text.alignleft") }

				ScrollView {
					NoteView(markdown: content, only: .transcript)
						.frame(maxWidth: .infinity, alignment: .leading).padding(20)
				}
				.tabItem { Label("Transcript", systemImage: "waveform") }

				ScrollView {
					Text(content)
						.font(.system(.body, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading).padding(20)
				}
				.tabItem { Label("Markdown", systemImage: "curlybraces") }
			}
			.padding(8)
		}
		.onAppear { titleField = meeting.title }
		.onChange(of: meeting.id) { titleField = meeting.title }
	}
}

/// Renders a meeting note's markdown as styled sections (Summary, Action items
/// as checkboxes, Transcript with speaker labels).
struct NoteView: View {
	enum Filter { case all, summary, transcript }
	let markdown: String
	var only: Filter = .all

	private var visibleSections: [Section] {
		sections().filter { sec in
			switch only {
			case .all: return true
			case .summary: return sec.title.lowercased() != "transcript"
			case .transcript: return sec.title.lowercased() == "transcript"
			}
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			ForEach(Array(visibleSections.enumerated()), id: \.offset) { _, sec in
				let isCard = sec.title.lowercased() != "transcript"
				VStack(alignment: .leading, spacing: 10) {
					Label(sec.title, systemImage: icon(for: sec.title))
						.font(.headline)
						.foregroundStyle(brand)
					body(for: sec)
				}
				.padding(isCard ? 16 : 0)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background {
					if isCard { RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)) }
				}
			}
		}
		.frame(maxWidth: 780, alignment: .leading)
		.textSelection(.enabled)
	}

	private struct Section { let title: String; let lines: [String] }

	private func icon(for title: String) -> String {
		switch title.lowercased() {
		case "short summary": return "text.quote"
		case "summary": return "text.alignleft"
		case "topics discussed", "topics", "discussion": return "bubble.left.and.bubble.right"
		case "action items": return "checklist"
		case "transcript": return "waveform"
		default: return "doc.text"
		}
	}

	@ViewBuilder
	private func body(for sec: Section) -> some View {
		let title = sec.title.lowercased()
		if title == "action items" {
			VStack(alignment: .leading, spacing: 6) {
				ForEach(Array(sec.lines.enumerated()), id: \.offset) { _, line in actionItem(line) }
			}
		} else if title == "transcript" {
			VStack(alignment: .leading, spacing: 8) {
				ForEach(Array(sec.lines.enumerated()), id: \.offset) { _, line in transcriptLine(line) }
			}
		} else {
			richText(sec.lines)
		}
	}

	/// Renders paragraphs, `### ` sub-headings (e.g. topic blocks), and `- ` bullets.
	@ViewBuilder
	private func richText(_ lines: [String]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
				let line = raw.trimmingCharacters(in: .whitespaces)
				if line.hasPrefix("### ") {
					Text(line.dropFirst(4))
						.font(.subheadline.weight(.semibold))
						.padding(.top, 4)
				} else if line.hasPrefix("- ") {
					HStack(alignment: .firstTextBaseline, spacing: 8) {
						Text("•").foregroundStyle(.secondary)
						inline(String(line.dropFirst(2)))
					}
				} else if !line.isEmpty {
					inline(line)
				}
			}
		}
	}

	@ViewBuilder
	private func actionItem(_ line: String) -> some View {
		let t = line.trimmingCharacters(in: .whitespaces)
		if t.hasPrefix("- [ ]") || t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
			let checked = t.hasPrefix("- [x]") || t.hasPrefix("- [X]")
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Image(systemName: checked ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(checked ? .green : .secondary)
				inline(String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces))
			}
		} else if t.hasPrefix("- ") {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text("•").foregroundStyle(.secondary)
				inline(String(t.dropFirst(2)))
			}
		} else {
			inline(t)
		}
	}

	@ViewBuilder
	private func transcriptLine(_ line: String) -> some View {
		if let (speaker, rest) = speakerSplit(line) {
			HStack(alignment: .top, spacing: 10) {
				Text(speaker)
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.white)
					.padding(.horizontal, 7).padding(.vertical, 2)
					.background(speaker == "You" ? brand : Color.gray, in: Capsule())
					.frame(width: 54, alignment: .leading)
				inline(rest).frame(maxWidth: .infinity, alignment: .leading)
			}
		} else {
			inline(line)
		}
	}

	private func speakerSplit(_ line: String) -> (String, String)? {
		for s in ["You", "Them"] {
			let p = "**\(s):**"
			if line.hasPrefix(p) { return (s, String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)) }
		}
		return nil
	}

	private func inline(_ s: String) -> Text {
		if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
			return Text(a)
		}
		return Text(s)
	}

	/// Strip frontmatter + the H1, then split into `## ` sections.
	private func sections() -> [Section] {
		var text = markdown
		if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
			text = String(text[end.upperBound...])
		}
		var result: [Section] = []
		var current: String?
		var buffer: [String] = []
		func flush() {
			if let c = current {
				let lines = buffer.map { $0 }.drop(while: { $0.isEmpty }).reversed().drop(while: { $0.isEmpty }).reversed()
				result.append(Section(title: c, lines: Array(lines)))
			}
			buffer = []
		}
		for raw in text.components(separatedBy: "\n") {
			if raw.hasPrefix("## ") { flush(); current = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
			else if raw.hasPrefix("# ") { continue }
			else if current != nil { buffer.append(raw) }
		}
		flush()
		return result
	}
}