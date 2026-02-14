import AppKit

class StatusBarController: NSObject, NSMenuDelegate {
    private lazy var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = SessionMonitor()
    private var displayedCount = -1
    private var animationTimer: Timer?
    private var animationStep = 0
    private var wasAttention = false

    private lazy var cachedIdleIcon: NSImage = IconRenderer.makeIdleIcon()

    func start() {
        monitor.ensureDirectories()

        guard monitor.acquireLock() else {
            NSLog("[claude-notification] Another instance is already running, exiting")
            NSApplication.shared.terminate(nil)
            return
        }

        setupStatusItem()

        monitor.onStateChange = { [weak self] in
            self?.updateState()
        }

        updateState()
        monitor.startMonitor()
        monitor.startCleanupTimer()
        NSLog("[claude-notification] Started")
    }

    func stop() {
        monitor.stopCleanupTimer()
        monitor.stopMonitor()
        monitor.releaseLock()
        NSLog("[claude-notification] Stopped")
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - State

    private func updateState() {
        let count = monitor.activeSessionCount()

        if count != displayedCount {
            let isAttention = count > 0
            let stateChanged = isAttention != wasAttention
            displayedCount = count

            if stateChanged {
                wasAttention = isAttention
                animateTransition()
            } else {
                updateDisplay()
            }
        }
    }

    // MARK: - Animation

    private func animateTransition() {
        animationStep = 0
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: Constants.animationFrameDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.animationStep += 1

            if self.animationStep >= Constants.animationSteps {
                timer.invalidate()
                self.animationTimer = nil
                self.updateDisplay()
            } else {
                let t = CGFloat(self.animationStep) / CGFloat(Constants.animationSteps)
                let eased = t * t * (3 - 2 * t) // smoothstep
                self.statusItem.button?.image = IconRenderer.makeAnimationFrame(
                    toAttention: self.displayedCount > 0, progress: eased)
            }
        }
    }

    // MARK: - Display

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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
