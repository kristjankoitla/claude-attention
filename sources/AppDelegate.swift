import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
