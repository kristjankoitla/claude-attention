import Foundation

class SessionMonitor {
    var onStateChange: (() -> Void)?

    let store: SessionStore

    private let directoryMonitor: DirectoryMonitor
    private let processLock: ProcessLock
    private var cleanupTimer: Timer?

    init() {
        let home = NSHomeDirectory()
        let baseDir = (home as NSString).appendingPathComponent(".claude-notification")
        let sessionDir = (baseDir as NSString).appendingPathComponent("sessions")

        store = SessionStore(sessionDir: sessionDir)
        directoryMonitor = DirectoryMonitor(path: sessionDir)
        processLock = ProcessLock(
            path: (baseDir as NSString).appendingPathComponent(".lock")
        )
    }

    /// Create the sessions directory if it doesn't exist.
    func ensureDirectories() {
        store.ensureDirectories()
    }

    /// Acquire the single-instance lock.
    func acquireLock() -> Bool {
        processLock.acquire()
    }

    /// Release the single-instance lock.
    func releaseLock() {
        processLock.release()
    }

    /// Start directory monitoring, cleanup timer, and begin monitoring.
    func start() {
        directoryMonitor.onRetry = { [weak self] in
            self?.store.ensureDirectories()
        }

        directoryMonitor.onChange = { [weak self] in
            self?.onStateChange?()
        }

        directoryMonitor.start()

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Constants.cleanupInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.store.cleanup()
            self.onStateChange?()
        }
    }

    /// Stop all monitoring and release resources.
    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        directoryMonitor.stop()
    }

    /// Count the active session files.
    func activeSessionCount() -> Int {
        store.activeSessionCount()
    }
}
