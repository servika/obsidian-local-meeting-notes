import Foundation

/// Downloads a whisper.cpp ggml model into ~/models with progress, for users
/// who don't have a local model yet.
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
	@Published var isDownloading = false
	@Published var progress: Double = 0
	@Published var message = ""

	static let available = [
		"tiny", "tiny.en", "base", "base.en", "small", "small.en",
		"medium", "medium.en", "large-v3-turbo",
	]

	private var session: URLSession?
	private var destURL: URL?
	private var onDone: ((URL?) -> Void)?

	func download(model: String, completion: @escaping (URL?) -> Void) {
		guard !isDownloading else { return }
		let dir = ("~/models" as NSString).expandingTildeInPath
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		let fileName = "ggml-\(model).bin"
		let dest = URL(fileURLWithPath: dir).appendingPathComponent(fileName)
		guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)") else {
			completion(nil); return
		}
		destURL = dest
		onDone = completion
		isDownloading = true
		progress = 0
		message = "Downloading \(fileName)…"
		let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
		session = s
		s.downloadTask(with: url).resume()
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
		didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard totalBytesExpectedToWrite > 0 else { return }
		let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
		DispatchQueue.main.async { self.progress = p }
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		guard let dest = destURL else { finish(nil); return }
		try? FileManager.default.removeItem(at: dest)
		do {
			try FileManager.default.moveItem(at: location, to: dest)
			finish(dest)
		} catch {
			finish(nil)
		}
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if let error = error {
			DispatchQueue.main.async { self.message = "Download failed: \(error.localizedDescription)" }
			finish(nil)
		}
	}

	private func finish(_ url: URL?) {
		DispatchQueue.main.async {
			self.isDownloading = false
			if let url = url { self.progress = 1; self.message = "Saved \(url.lastPathComponent)" }
			self.onDone?(url)
			self.onDone = nil
		}
		session?.finishTasksAndInvalidate()
		session = nil
	}
}