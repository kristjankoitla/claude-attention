import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = StatusBarController()

    /// Start the status bar controller once the app is ready.
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    /// Clean up monitoring and release the lock before exit.
    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
