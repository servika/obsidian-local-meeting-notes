import Foundation

/// Checks GitHub Releases for a newer macOS build and exposes an unobtrusive
/// "update available" state. Privacy-safe: a single outbound request to the
/// public GitHub API, throttled to once a day, no telemetry. The user always
/// downloads manually (we link to the release page) - nothing auto-installs.
@MainActor
final class UpdateChecker: ObservableObject {
	/// Latest macOS release version (e.g. "0.27.0"), if newer than the running app.
	@Published private(set) var latestVersion: String?
	@Published private(set) var releaseURL: URL?
	@Published private(set) var status = ""
	@Published private(set) var checking = false

	private let current = appVersion
	private let lastCheckKey = "lastUpdateCheck"
	private let dismissedKey = "dismissedUpdateVersion"

	/// True when a newer version exists and the user hasn't dismissed it.
	var updateAvailable: Bool {
		guard let latest = latestVersion, Self.isNewer(latest, than: current) else { return false }
		return UserDefaults.standard.string(forKey: dismissedKey) != latest
	}

	/// Stop showing the banner for the current latest version (until a newer one).
	func dismiss() {
		if let latest = latestVersion { UserDefaults.standard.set(latest, forKey: dismissedKey) }
		objectWillChange.send()
	}

	/// Check on launch, at most once every 24h.
	func checkIfDue() {
		let last = UserDefaults.standard.double(forKey: lastCheckKey)
		if Date().timeIntervalSince1970 - last < 86_400 { return }
		check()
	}

	/// Check now (also used by the manual "Check for updates" button).
	func check() {
		guard !checking else { return }
		checking = true
		status = "Checking…"
		// Pull the releases list (newest first) so we can pick the latest *macOS*
		// release - tags look like "v0.26.2"; Windows releases are "win-v*".
		let url = URL(string: "https://api.github.com/repos/servika/ai-meeting-notes/releases?per_page=20")!
		var req = URLRequest(url: url, timeoutInterval: 15)
		req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		URLSession.shared.dataTask(with: req) { data, _, _ in
			Task { @MainActor in self.handle(data) }
		}.resume()
	}

	private func handle(_ data: Data?) {
		checking = false
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
		guard let data,
			let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
			status = "Couldn't check for updates."
			return
		}
		for rel in arr {
			if rel["draft"] as? Bool == true || rel["prerelease"] as? Bool == true { continue }
			guard let tag = rel["tag_name"] as? String,
				tag.hasPrefix("v"), !tag.hasPrefix("win-") else { continue }
			latestVersion = String(tag.dropFirst()) // drop the "v"
			releaseURL = (rel["html_url"] as? String).flatMap(URL.init)
				?? URL(string: "https://github.com/servika/ai-meeting-notes/releases/latest")
			status = updateAvailable ? "" : "You're on the latest version (\(current))."
			return
		}
		status = "No releases found."
	}

	/// Dotted-numeric "greater than" (e.g. 0.27.0 > 0.26.2). Ignores any suffix.
	static func isNewer(_ a: String, than b: String) -> Bool {
		func parts(_ s: String) -> [Int] {
			s.prefix { $0.isNumber || $0 == "." }.split(separator: ".").map { Int($0) ?? 0 }
		}
		let pa = parts(a), pb = parts(b)
		for i in 0..<max(pa.count, pb.count) {
			let x = i < pa.count ? pa[i] : 0
			let y = i < pb.count ? pb[i] : 0
			if x != y { return x > y }
		}
		return false
	}
}