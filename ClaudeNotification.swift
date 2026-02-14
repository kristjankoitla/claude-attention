import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

// MARK: - Status Bar Controller

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var cleanupTimer: Timer?
    private var displayedCount = -1
    private var lockFileDescriptor: Int32 = -1
    private var animationTimer: Timer?
    private var animationStep = 0
    private let animationSteps = 40
    private var wasAttention = false

    private let baseDir: String = {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".claude-notification")
    }()

    private var sessionDir: String {
        (baseDir as NSString).appendingPathComponent("sessions")
    }

    private var lockPath: String {
        (baseDir as NSString).appendingPathComponent(".lock")
    }

    private lazy var cachedIdleIcon: NSImage = makeIdleIcon()

    func start() {
        ensureDirectories()

        guard acquireLock() else {
            NSLog("[claude-notification] Another instance is already running, exiting")
            NSApplication.shared.terminate(nil)
            return
        }

        setupStatusItem()
        updateState()
        startMonitor()
        startCleanupTimer()
        NSLog("[claude-notification] Started")
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        stopMonitor()
        releaseLock()
        NSLog("[claude-notification] Stopped")
    }

    // MARK: - Single Instance Lock

    private func acquireLock() -> Bool {
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

    private func releaseLock() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    // MARK: - Setup

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(
            atPath: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Directory Monitoring

    private func startMonitor() {
        stopMonitor()

        let fd = open(sessionDir, O_EVTONLY)
        guard fd >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.ensureDirectories()
                self?.startMonitor()
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.updateState()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileMonitorSource = source
    }

    private func stopMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.cleanup()
            self?.updateState()
        }
    }

    private func cleanup() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionDir) else { return }
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        let staleThreshold: TimeInterval = 900 // 15 minutes

        for file in files where !file.hasPrefix(".") {
            let path = (sessionDir as NSString).appendingPathComponent(file)

            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
                if let pidStr = parts.first, let pid = pid_t(pidStr) {
                    if kill(pid, 0) != 0 && errno == ESRCH {
                        try? fm.removeItem(atPath: path)
                        continue
                    }

                    // Remove if session has been waiting too long
                    if parts.count > 1, let timestamp = Double(parts[1]),
                       now - timestamp > staleThreshold {
                        try? fm.removeItem(atPath: path)
                        continue
                    }
                }
            }

            // Fallback: remove files older than 15 minutes
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > staleThreshold {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    // MARK: - State

    private func activeSessionCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: sessionDir)) ?? []
        return files.filter { !$0.hasPrefix(".") }.count
    }

    private func updateState() {
        let count = activeSessionCount()

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
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.animationStep += 1

            if self.animationStep >= self.animationSteps {
                timer.invalidate()
                self.animationTimer = nil
                self.updateDisplay()
            } else {
                let t = CGFloat(self.animationStep) / CGFloat(self.animationSteps)
                let eased = t * t * (3 - 2 * t) // smoothstep
                self.drawAnimationFrame(progress: eased)
            }
        }
    }

    private func drawAnimationFrame(progress: CGFloat) {
        let toAttention = displayedCount > 0
        let fromRatio: CGFloat = toAttention ? 0.35 : 0.65
        let toRatio: CGFloat = toAttention ? 0.65 : 0.35
        let currentRatio = fromRatio + (toRatio - fromRatio) * progress
        let rotation = progress * .pi

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            self.sparklePath(in: rect.insetBy(dx: 1, dy: 1), innerRatio: currentRatio, rotation: rotation).fill()
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Display

    private func updateDisplay() {
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        if displayedCount <= 0 {
            statusItem.button?.image = cachedIdleIcon
            statusItem.button?.toolTip = "Claude - All clear"
        } else {
            statusItem.button?.image = makeCountIcon(displayedCount)
            statusItem.button?.toolTip = "\(displayedCount) Claude session\(displayedCount == 1 ? "" : "s") need\(displayedCount == 1 ? "s" : "") attention"
        }
    }

    // MARK: - Icon Drawing

    private func makeIdleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            self.sparklePath(in: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func makeCountIcon(_ count: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Fat sparkle (wider inner radius for more body)
            let diamond = self.sparklePath(in: rect.insetBy(dx: 1, dy: 1), innerRatio: 0.65)

            // Draw sparkle, then punch out the Roman numeral
            let str = self.toRoman(count)
            let fontSize: CGFloat
            switch str.count {
            case 1:    fontSize = 10
            case 2:    fontSize = 9
            case 3:    fontSize = 7.5
            default:   fontSize = 6
            }
            let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let attrStr = NSAttributedString(string: str, attributes: attrs)
            let textSize = attrStr.size()
            let textOrigin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - font.capHeight) / 2
            )

            // Create text path for cutout
            let textPath = CGMutablePath()
            let line = CTLineCreateWithAttributedString(attrStr)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            for run in runs {
                let runFont = (CTRunGetAttributes(run) as Dictionary)[kCTFontAttributeName] as! CTFont
                let glyphCount = CTRunGetGlyphCount(run)
                for i in 0..<glyphCount {
                    var glyph = CGGlyph()
                    var position = CGPoint()
                    CTRunGetGlyphs(run, CFRangeMake(i, 1), &glyph)
                    CTRunGetPositions(run, CFRangeMake(i, 1), &position)
                    if let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) {
                        var transform = CGAffineTransform(translationX: textOrigin.x + position.x,
                                                          y: textOrigin.y + position.y)
                        textPath.addPath(glyphPath, transform: transform)
                    }
                }
            }

            // Composite: diamond minus text
            let compositePath = NSBezierPath(cgPath: textPath)
            diamond.append(compositePath)
            diamond.windingRule = .evenOdd

            NSColor.black.setFill()
            diamond.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func sparklePath(in rect: NSRect, innerRatio: CGFloat = 0.35, rotation: CGFloat = 0) -> NSBezierPath {
        let cx = rect.midX
        let cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio

        let path = NSBezierPath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0 + rotation
            let r = (i % 2 == 0) ? outerR : innerR
            let point = NSPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        return path
    }

    // MARK: - Roman Numerals

    private func toRoman(_ number: Int) -> String {
        let values = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),
                      (100,"C"),(90,"XC"),(50,"L"),(40,"XL"),
                      (10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var result = ""
        var n = number
        for (value, numeral) in values {
            while n >= value {
                result += numeral
                n -= value
            }
        }
        return result
    }

    // MARK: - Menu Delegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        let count = activeSessionCount()
        let title = count > 0
            ? "\(count) session\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention"
            : "All clear"

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

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
