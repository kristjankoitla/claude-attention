import Foundation

class SessionMonitor {
    var onStateChange: (() -> Void)?

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var cleanupTimer: Timer?
    private var monitorRetryCount = 0
    private let maxMonitorRetries = 10

    private let baseDir: String = {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".claude-notification")
    }()

    private lazy var processLock = ProcessLock(
        path: (baseDir as NSString).appendingPathComponent(".lock")
    )

    var sessionDir: String {
        (baseDir as NSString).appendingPathComponent("sessions")
    }

    /// Create the sessions directory (and parents) if it doesn't exist.
    func ensureDirectories() {
        try? FileManager.default.createDirectory(
            atPath: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    // MARK: - Single Instance Lock

    /// Acquire the single-instance lock to prevent duplicate processes.
    func acquireLock() -> Bool {
        processLock.acquire()
    }

    /// Release the single-instance lock on shutdown.
    func releaseLock() {
        processLock.release()
    }

    // MARK: - Directory Monitoring

    /// Watch the sessions directory for filesystem changes, retrying with backoff on failure.
    func startMonitor() {
        stopMonitor()

        let fd = open(sessionDir, O_EVTONLY)
        guard fd >= 0 else {
            scheduleMonitorRetry()
            return
        }
        monitorRetryCount = 0

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.onStateChange?() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitorSource = source
    }

    /// Cancel the filesystem watcher.
    func stopMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    // MARK: - Cleanup Timer

    /// Schedule periodic removal of stale session files.
    func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Constants.cleanupInterval, repeats: true) { [weak self] _ in
            self?.cleanup()
            self?.onStateChange?()
        }
    }

    /// Stop the periodic cleanup timer.
    func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    // MARK: - Session Count

    /// Count the active (non-hidden) session files.
    func activeSessionCount() -> Int {
        sessionFiles().count
    }

    // MARK: - Private

    /// Retry opening the sessions directory with exponential backoff.
    private func scheduleMonitorRetry() {
        guard monitorRetryCount < maxMonitorRetries else {
            NSLog("[claude-notification] Failed to open session directory after %d retries, giving up", monitorRetryCount)
            return
        }
        monitorRetryCount += 1
        let delay = min(Double(1 << monitorRetryCount), 60.0)
        NSLog("[claude-notification] Session directory not available, retry %d/%d in %.0fs",
              monitorRetryCount, maxMonitorRetries, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.ensureDirectories()
            self?.startMonitor()
        }
    }

    /// List non-hidden filenames in the sessions directory.
    private func sessionFiles() -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: sessionDir)
                .filter { !$0.hasPrefix(".") }
        } catch {
            NSLog("[claude-notification] Failed to list session directory: %@", error.localizedDescription)
            return []
        }
    }

    /// Remove session files that are no longer valid.
    private func cleanup() {
        let now = Date().timeIntervalSince1970
        for file in sessionFiles() {
            let path = (sessionDir as NSString).appendingPathComponent(file)
            guard isSessionStale(atPath: path, now: now) else { continue }
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                NSLog("[claude-notification] Failed to remove session %@: %@", file, error.localizedDescription)
            }
        }
    }

    /// Determine if a session file is stale: dead process, expired timestamp, or old modification date.
    private func isSessionStale(atPath path: String, now: TimeInterval) -> Bool {
        if let record = parseSessionFile(atPath: path) {
            return isProcessDead(record.pid)
                || record.timestamp.map({ now - $0 > Constants.staleThreshold }) ?? false
        }
        return isFileOlderThanThreshold(atPath: path, now: now)
    }

    // MARK: - Session File Parsing

    private struct SessionRecord {
        let pid: pid_t
        let timestamp: TimeInterval?
    }

    /// Parse a session file's "PID:timestamp" content into a structured record.
    private func parseSessionFile(atPath path: String) -> SessionRecord? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard let pidStr = parts.first, let pid = pid_t(pidStr) else {
            return nil
        }
        let timestamp = parts.count > 1 ? Double(parts[1]) : nil
        return SessionRecord(pid: pid, timestamp: timestamp)
    }

    /// Check if a process no longer exists.
    private func isProcessDead(_ pid: pid_t) -> Bool {
        kill(pid, 0) != 0 && errno == ESRCH
    }

    /// Check if a file's modification date exceeds the stale threshold.
    private func isFileOlderThanThreshold(atPath path: String, now: TimeInterval) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return false
        }
        return now - modDate.timeIntervalSince1970 > Constants.staleThreshold
    }
}
