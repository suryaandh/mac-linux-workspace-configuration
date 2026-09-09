import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var notchWindowController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Defer to next run loop tick so NSScreen.main is ready
        DispatchQueue.main.async {
            self.setup()
        }
    }

    private func setup() {
        notchWindowController = NotchWindowController()

        MusicMonitor.shared.start()
        NotificationMonitor.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MusicMonitor.shared.stop()
        NotificationMonitor.shared.stop()
    }
}
