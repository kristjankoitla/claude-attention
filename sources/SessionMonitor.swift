import Foundation

class SessionMonitor {
    var onStateChange: (() -> Void)?

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var cleanupTimer: Timer?
    private var lockFileDescriptor: Int32 = -1
    private var monitorRetryCount = 0
    private let maxMonitorRetries = 10

    private let baseDir: String = {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".claude-notification")
    }()

    var sessionDir: String {
        (baseDir as NSString).appendingPathComponent("sessions")
    }

    private var lockPath: String {
        (baseDir as NSString).appendingPathComponent(".lock")
    }

    func ensureDirectories() {
        try? FileManager.default.createDirectory(
            atPath: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    // MARK: - Single Instance Lock

    func acquireLock() -> Bool {
        lockFileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard lockFileDescriptor >= 0 else {
            return false
        }
        if flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            close(lockFileDescriptor)
            lockFileDescriptor = -1
            return false
        }
        return true
    }

    func releaseLock() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    // MARK: - Directory Monitoring

    func startMonitor() {
        stopMonitor()

        let fd = open(sessionDir, O_EVTONLY)
        guard fd >= 0 else {
            guard monitorRetryCount < maxMonitorRetries else {
                NSLog("[claude-notification] Failed to open session directory after %d retries, giving up", monitorRetryCount)
                return
            }
            monitorRetryCount += 1
            let delay = min(Double(1 << monitorRetryCount), 60.0) // exponential backoff, max 60s
            NSLog("[claude-notification] Session directory not available, retry %d/%d in %.0fs", monitorRetryCount, maxMonitorRetries, delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.ensureDirectories()
                self?.startMonitor()
            }
            return
        }
        monitorRetryCount = 0

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onStateChange?()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileMonitorSource = source
    }

    func stopMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    // MARK: - Cleanup Timer

    func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Constants.cleanupInterval, repeats: true) { [weak self] _ in
            self?.cleanup()
            self?.onStateChange?()
        }
    }

    func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    // MARK: - Cleanup

    private func cleanup() {
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: sessionDir)
        } catch {
            NSLog("[claude-notification] Failed to list session directory: %@", error.localizedDescription)
            return
        }

        let fm = FileManager.default
        let now = Date().timeIntervalSince1970

        for file in files where !file.hasPrefix(".") {
            let path = (sessionDir as NSString).appendingPathComponent(file)

            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
                if let pidStr = parts.first, let pid = pid_t(pidStr) {
                    if kill(pid, 0) != 0 && errno == ESRCH {
                        do {
                            try fm.removeItem(atPath: path)
                        } catch {
                            NSLog("[claude-notification] Failed to remove stale session %@: %@", file, error.localizedDescription)
                        }
                        continue
                    }

                    if parts.count > 1, let timestamp = Double(parts[1]),
                       now - timestamp > Constants.staleThreshold {
                        do {
                            try fm.removeItem(atPath: path)
                        } catch {
                            NSLog("[claude-notification] Failed to remove expired session %@: %@", file, error.localizedDescription)
                        }
                        continue
                    }
                }
            }

            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > Constants.staleThreshold {
                do {
                    try fm.removeItem(atPath: path)
                } catch {
                    NSLog("[claude-notification] Failed to remove old session %@: %@", file, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Session Count

    func activeSessionCount() -> Int {
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: sessionDir)
        } catch {
            NSLog("[claude-notification] Failed to read session directory: %@", error.localizedDescription)
            return 0
        }
        return files.filter { !$0.hasPrefix(".") }.count
    }
}
