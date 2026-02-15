import Foundation

class DirectoryMonitor {
    var onChange: (() -> Void)?

    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var retryCount = 0
    private let maxRetries = 10

    init(path: String) {
        self.path = path
    }

    /// Watch the directory for filesystem changes, retrying with backoff on failure.
    func start() {
        stop()

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry()
            return
        }
        retryCount = 0

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.onChange?() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    /// Cancel the filesystem watcher.
    func stop() {
        source?.cancel()
        source = nil
    }

    // MARK: - Private

    /// Retry opening the directory with exponential backoff.
    private func scheduleRetry() {
        guard retryCount < maxRetries else {
            NSLog("[claude-notification] Failed to open directory after %d retries, giving up", retryCount)
            return
        }
        retryCount += 1
        let delay = min(Double(1 << retryCount), 60.0)
        NSLog("[claude-notification] Directory not available, retry %d/%d in %.0fs",
              retryCount, maxRetries, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.start()
        }
    }
}
