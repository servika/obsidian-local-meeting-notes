import SwiftUI

struct ContentView: View {
	@EnvironmentObject var settings: AppSettings
	@EnvironmentObject var store: MeetingStore
	@EnvironmentObject var controller: RecordingController
	@State private var selection: Meeting.ID?

	var body: some View {
		NavigationSplitView {
			VStack(spacing: 0) {
				List(store.meetings, selection: $selection) { meeting in
					VStack(alignment: .leading, spacing: 2) {
						Text(meeting.title).lineLimit(1)
						Text(meeting.modified, style: .date)
							.font(.caption).foregroundStyle(.secondary)
					}
				}
				Divider()
				recordPanel.padding(12)
			}
			.navigationSplitViewColumnWidth(min: 240, ideal: 280)
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
					onRegenerate: { controller.regenerate(meeting) })
			} else {
				ContentUnavailableView("No meeting selected", systemImage: "waveform",
					description: Text("Record a meeting, or pick one from the list."))
			}
		}
		.onAppear { store.reload(folder: settings.meetingsDirURL) }
	}

	private var recordPanel: some View {
		VStack(alignment: .leading, spacing: 8) {
			Button(controller.isRecording ? "Stop & Transcribe" : "Record") {
				controller.toggle()
			}
			.controlSize(.large)
			.disabled(controller.busy)
			.keyboardShortcut(.defaultAction)

			if controller.busy {
				ProgressView(value: controller.progress)
					.progressViewStyle(.linear)
				HStack {
					Text("\(Int(controller.progress * 100))%")
					Spacer()
					Text(controller.elapsed)
				}
				.font(.caption).foregroundStyle(.secondary)
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
			Text(label).font(.caption).frame(width: 50, alignment: .leading)
			ProgressView(value: Double(min(max(level, 0), 1)))
				.progressViewStyle(.linear)
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
	@State private var titleField = ""

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 8) {
				TextField("Title", text: $titleField)
					.textFieldStyle(.roundedBorder)
					.font(.title3)
					.onSubmit { onRename(titleField) }
				Button("Rename") { onRename(titleField) }
					.disabled(titleField.trimmingCharacters(in: .whitespaces).isEmpty || titleField == meeting.title)
				Button { onRegenerate() } label: { Label("Re-generate", systemImage: "arrow.clockwise") }
					.disabled(busy)
			}
			.padding()

			if busy {
				VStack(alignment: .leading, spacing: 4) {
					ProgressView(value: progress).progressViewStyle(.linear)
					Text(status).font(.caption).foregroundStyle(.secondary)
				}
				.padding(.horizontal)
				.padding(.bottom, 8)
			}

			Divider()

			ScrollView {
				Text(content)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding()
			}
		}
		.navigationTitle(meeting.title)
		.onAppear { titleField = meeting.title }
		.onChange(of: meeting.id) { titleField = meeting.title }
	}
}