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
				MeetingDetail(title: meeting.title, markdown: store.content(of: meeting))
			} else {
				ContentUnavailableView("No meeting selected", systemImage: "waveform",
					description: Text("Record a meeting, or pick one from the list."))
			}
		}
		.onAppear { store.reload(folder: settings.meetingsDirURL) }
	}

	private var recordPanel: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Button(controller.isRecording ? "Stop & Transcribe" : "Record") {
					controller.toggle()
				}
				.controlSize(.large)
				.disabled(controller.busy)
				.keyboardShortcut(.defaultAction)
				if controller.busy { ProgressView().controlSize(.small) }
			}
			LevelBar(label: "System", level: controller.systemLevel)
			LevelBar(label: "Mic", level: controller.micLevel)
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
	let title: String
	let markdown: String
	var body: some View {
		ScrollView {
			Text(markdown)
				.textSelection(.enabled)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()
		}
		.navigationTitle(title)
	}
}