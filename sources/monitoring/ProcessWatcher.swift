import Foundation

class ProcessWatcher {
    var onChange: (() -> Void)?

    private var sources: [pid_t: DispatchSourceProcess] = [:]

    /// Reconcile watched PIDs against the current pid-to-path map.
    /// Stops watchers for PIDs no longer present, starts watchers for new PIDs.
    func refresh(pids: [pid_t: String], store: SessionStore) {
        // Stop watchers for PIDs that no longer have session files
        for pid in sources.keys where pids[pid] == nil {
            sources[pid]?.cancel()
            sources.removeValue(forKey: pid)
        }

        // Start watchers for new PIDs
        for (pid, path) in pids where sources[pid] == nil {
            guard !store.isProcessDead(pid) else {
                store.removeSession(atPath: path)
                onChange?()
                continue
            }

            let source = DispatchSource.makeProcessSource(
                identifier: pid,
                eventMask: .exit,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                store.removeSession(atPath: path)
                self.sources[pid]?.cancel()
                self.sources.removeValue(forKey: pid)
                self.onChange?()
            }
            source.setCancelHandler {}
            source.resume()
            sources[pid] = source
        }
    }

    /// Cancel all active process exit watchers.
    func stop() {
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
    }
}
