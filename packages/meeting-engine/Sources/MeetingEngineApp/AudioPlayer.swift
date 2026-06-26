// Combined two-track playback for a meeting.
//
// A meeting is stored as two separate recordings - the mic ("You") and the
// system audio ("Them"). To let the user listen to the meeting as one thing, we
// stitch both tracks into a single AVMutableComposition (one composition track
// each, starting at zero) so AVPlayer mixes them on playback. The view then only
// drives one transport: play/pause, restart, ±15 s, a scrubbable position bar,
// and a playback-speed menu.

import AVFoundation
import SwiftUI

/// Drives mixed playback of a meeting's mic + system tracks behind one transport.
@MainActor
final class MeetingAudioPlayer: ObservableObject {
	@Published private(set) var isPlaying = false
	@Published private(set) var ready = false
	@Published var currentTime: Double = 0   // seconds; also the scrub position
	@Published private(set) var duration: Double = 0
	/// Selected playback speed; applied immediately while playing.
	@Published var rate: Float = 1 { didSet { if isPlaying { player?.rate = rate } } }

	/// Speeds offered in the UI.
	static let speeds: [Float] = [0.5, 1, 1.5, 2, 3, 5]

	private var player: AVPlayer?
	private var timeObserver: Any?
	private var endObserver: NSObjectProtocol?
	private var loadedURLs: [URL] = []
	private var scrubbing = false

	/// (Re)load the given track URLs into one mixed timeline. No-op when the set is
	/// unchanged, so re-selecting the same meeting doesn't restart playback.
	func load(urls: [URL]) async {
		guard urls != loadedURLs else { return }
		teardown()
		loadedURLs = urls
		guard !urls.isEmpty else { return }

		let composition = AVMutableComposition()
		var maxDuration = CMTime.zero
		for url in urls {
			let asset = AVURLAsset(url: url)
			guard let src = try? await asset.loadTracks(withMediaType: .audio).first,
				let dur = try? await asset.load(.duration),
				let track = composition.addMutableTrack(
					withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
			else { continue }
			try? track.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
			if dur > maxDuration { maxDuration = dur }
		}
		guard maxDuration > .zero else { return }

		let item = AVPlayerItem(asset: composition)
		// Keep voices intelligible (pitch-corrected) across the wide 0.5×…5× range.
		item.audioTimePitchAlgorithm = .timeDomain
		let player = AVPlayer(playerItem: item)
		player.actionAtItemEnd = .pause
		self.player = player
		duration = maxDuration.seconds

		// Drive the position bar ~10×/sec, except while the user is scrubbing.
		timeObserver = player.addPeriodicTimeObserver(
			forInterval: CMTime(value: 1, timescale: 10), queue: .main
		) { [weak self] time in
			MainActor.assumeIsolated {
				guard let self, !self.scrubbing else { return }
				self.currentTime = time.seconds
			}
		}
		endObserver = NotificationCenter.default.addObserver(
			forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				self.isPlaying = false
				self.currentTime = self.duration
			}
		}
		ready = true
	}

	func togglePlay() { isPlaying ? pause() : play() }

	func play() {
		guard let player else { return }
		// Restart from the top when starting from the very end.
		if currentTime >= duration - 0.05 { seek(to: 0) }
		player.rate = rate
		isPlaying = true
	}

	func pause() {
		player?.pause()
		isPlaying = false
	}

	func restart() { seek(to: 0) }

	/// Jump by ±seconds, clamped to the track.
	func skip(by seconds: Double) {
		seek(to: min(max(currentTime + seconds, 0), duration))
	}

	/// Seek to an absolute time. Accurate seek so the position bar and audio agree.
	func seek(to seconds: Double) {
		guard let player else { return }
		let t = min(max(seconds, 0), duration)
		currentTime = t
		player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
			toleranceBefore: .zero, toleranceAfter: .zero)
	}

	// Scrub support: while dragging we suppress the time observer and only move the
	// thumb; on release we seek once (avoids a seek storm during the drag).
	func beginScrub() { scrubbing = true }
	func endScrub() { scrubbing = false; seek(to: currentTime) }

	func teardown() {
		if let timeObserver { player?.removeTimeObserver(timeObserver) }
		if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
		timeObserver = nil; endObserver = nil
		player?.pause(); player = nil
		isPlaying = false; ready = false
		currentTime = 0; duration = 0; loadedURLs = []
	}
}

/// Transport UI for `MeetingAudioPlayer`: restart, ±15 s, play/pause, a clickable
/// position bar (0…duration), time labels, and a speed menu.
struct AudioPlayerView: View {
	@ObservedObject var player: MeetingAudioPlayer

	var body: some View {
		VStack(spacing: 6) {
			HStack(spacing: 14) {
				Button { player.restart() } label: { Image(systemName: "backward.end.fill") }
					.help("Back to start")
				Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
					.help("Back 15 seconds")
				Button { player.togglePlay() } label: {
					Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
						.font(.title2)
				}
				.help(player.isPlaying ? "Pause" : "Play")
				.keyboardShortcut(.space, modifiers: [])
				Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
					.help("Forward 15 seconds")

				Spacer(minLength: 8)

				Menu {
					ForEach(MeetingAudioPlayer.speeds, id: \.self) { s in
						Button { player.rate = s } label: {
							if player.rate == s { Label(speedLabel(s), systemImage: "checkmark") }
							else { Text(speedLabel(s)) }
						}
					}
				} label: {
					Text(speedLabel(player.rate)).frame(minWidth: 34)
				}
				.menuStyle(.borderlessButton)
				.fixedSize()
				.help("Playback speed")
			}
			.buttonStyle(.borderless)

			HStack(spacing: 8) {
				Text(timeLabel(player.currentTime))
					.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
				Slider(
					value: $player.currentTime,
					in: 0...max(player.duration, 0.1),
					onEditingChanged: { editing in editing ? player.beginScrub() : player.endScrub() }
				)
				Text(timeLabel(player.duration))
					.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 20).padding(.vertical, 10)
		.disabled(!player.ready)
		.opacity(player.ready ? 1 : 0.5)
	}

	private func speedLabel(_ s: Float) -> String {
		s == s.rounded() ? "\(Int(s))×" : String(format: "%g×", s)
	}

	private func timeLabel(_ seconds: Double) -> String {
		let s = max(0, Int(seconds.rounded()))
		let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
		return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
	}
}