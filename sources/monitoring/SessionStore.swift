import Foundation

struct SessionRecord {
    let pid: pid_t
    let timestamp: TimeInterval?
}

class SessionStore {
    let sessionDir: String

    init(sessionDir: String) {
        self.sessionDir = sessionDir
    }

    /// Create the sessions directory (and parents) if it doesn't exist.
    func ensureDirectories() {
        try? FileManager.default.createDirectory(
            atPath: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// List non-hidden filenames in the sessions directory.
    func sessionFiles() -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: sessionDir)
                .filter { !$0.hasPrefix(".") }
        } catch {
            NSLog("[claude-notification] Failed to list session directory: %@", error.localizedDescription)
            return []
        }
    }

    /// Parse a session file's "PID:timestamp" content into a structured record.
    func parseSessionFile(atPath path: String) -> SessionRecord? {
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

    /// Count the active (non-hidden) session files.
    func activeSessionCount() -> Int {
        sessionFiles().count
    }

    /// Remove session files that are no longer valid.
    func cleanup() {
        let now = Date().timeIntervalSince1970
        for file in sessionFiles() {
            let path = (sessionDir as NSString).appendingPathComponent(file)
            guard isSessionStale(atPath: path, now: now) else { continue }
            removeSession(atPath: path)
        }
    }

    /// Remove a session file, logging on error.
    func removeSession(atPath path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            NSLog("[claude-notification] Failed to remove session %@: %@",
                  (path as NSString).lastPathComponent, error.localizedDescription)
        }
    }

    // MARK: - Private

    /// Determine if a session file is stale: dead process, expired timestamp, or old modification date.
    private func isSessionStale(atPath path: String, now: TimeInterval) -> Bool {
        if let record = parseSessionFile(atPath: path) {
            if kill(record.pid, 0) != 0 && errno == ESRCH { return true }
            if let ts = record.timestamp, now - ts > Constants.staleThreshold { return true }
        }
        return isFileOlderThanThreshold(atPath: path, now: now)
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
