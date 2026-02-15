import Foundation

class ProcessLock {
    private let path: String
    private var fileDescriptor: Int32 = -1

    init(path: String) {
        self.path = path
    }

    /// Attempt to acquire an exclusive, non-blocking file lock. Returns true on success.
    func acquire() -> Bool {
        fileDescriptor = open(path, O_CREAT | O_RDWR, 0o600)
        guard fileDescriptor >= 0 else {
            return false
        }
        if flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            close(fileDescriptor)
            fileDescriptor = -1
            return false
        }
        return true
    }

    /// Release the file lock and close the descriptor.
    func release() {
        if fileDescriptor >= 0 {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
}
