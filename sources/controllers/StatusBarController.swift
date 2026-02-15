import AppKit

class StatusBarController: NSObject, NSMenuDelegate {
    private lazy var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SessionMonitor()
    private let animation = AnimationController()
    private var displayedCount = -1

    private lazy var cachedIdleIcon: NSImage = IconRenderer.makeIdleIcon()

    /// Initialize directories, acquire the single-instance lock, wire up callbacks, and begin monitoring.
    func start() {
        monitor.ensureDirectories()

        guard monitor.acquireLock() else {
            NSLog("[claude-notification] Another instance is already running, exiting")
            NSApplication.shared.terminate(nil)
            return
        }

        setupStatusItem()

        animation.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
        }
        animation.onComplete = { [weak self] in
            self?.updateDisplay()
        }

        monitor.onStateChange = { [weak self] in
            self?.updateState()
        }

        updateState()
        monitor.start()
        NSLog("[claude-notification] Started")
    }

    /// Tear down monitoring and release the process lock.
    func stop() {
        monitor.stop()
        monitor.releaseLock()
        NSLog("[claude-notification] Stopped")
    }

    // MARK: - Setup

    /// Create the status bar menu and assign this controller as its delegate.
    private func setupStatusItem() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - State

    /// Check the current session count and trigger an animation or display update if it changed.
    private func updateState() {
        let count = monitor.activeSessionCount()

        if count != displayedCount {
            displayedCount = count
            animation.animate(toAttention: count > 0)
        }
    }

    // MARK: - Display

    /// Set the status bar icon and tooltip to reflect the current session count.
    private func updateDisplay() {
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        if displayedCount <= 0 {
            statusItem.button?.image = cachedIdleIcon
            statusItem.button?.toolTip = "Claude - All clear"
        } else {
            statusItem.button?.image = IconRenderer.makeCountIcon(displayedCount)
            statusItem.button?.toolTip = IconRenderer.statusText(for: displayedCount)
        }
    }

    // MARK: - Menu Delegate

    /// Build the dropdown menu with a status line and quit option each time it opens.
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        let count = monitor.activeSessionCount()
        let title = IconRenderer.statusText(for: count)

        let statusMenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Terminate the application when the user clicks Quit.
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
