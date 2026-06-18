import Foundation

/// Cooperative cancellation for the transcription pipeline. `cancel()` flips the
/// flag and terminates the currently-running child process (whisper-cli), so a
/// long transcription stops promptly.
public final class CancelToken {
	private let lock = NSLock()
	private var cancelled = false
	private var process: Process?

	public init() {}

	public var isCancelled: Bool {
		lock.lock(); defer { lock.unlock() }
		return cancelled
	}

	public func cancel() {
		lock.lock()
		cancelled = true
		let p = process
		lock.unlock()
		p?.terminate()
	}

	func register(_ p: Process) { lock.lock(); process = p; lock.unlock() }
	func clearProcess() { lock.lock(); process = nil; lock.unlock() }
}

public struct CancelledError: Error {
	public init() {}
}