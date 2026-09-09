import Cocoa

class NotificationMonitor {

    static let shared = NotificationMonitor()
    private init() {}

    private var observer: NSObjectProtocol?

    func start() {
        // Listen for distributed notifications that apps post when delivering banners
        // This catches notifications that go through NSUserNotificationCenter / UNUserNotificationCenter
        let dnc = DistributedNotificationCenter.default()

        // macOS posts com.apple.springboard.notificationReceived for each banner
        observer = dnc.addObserver(
            forName: NSNotification.Name("com.apple.springboard.notificationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handle(notification)
        }

        // Also watch for NSUserNotificationCenter (legacy apps / some system apps)
        NSUserNotificationCenter.default.delegate = NotificationCenterDelegate.shared
    }

    func stop() {
        if let observer = observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func handle(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        // Extract fields from the notification payload
        let appName = (userInfo["app"] as? String)
            ?? (userInfo["bundleID"] as? String)
            ?? "Notification"
        let message = (userInfo["body"] as? String)
            ?? (userInfo["subtitle"] as? String)
            ?? (userInfo["title"] as? String)
            ?? ""

        guard !message.isEmpty else { return }

        // Try to get the app icon from the bundle identifier
        let icon: NSImage? = {
            if let bundleID = userInfo["bundleID"] as? String,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }
            return nil
        }()

        DispatchQueue.main.async {
            guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
            appDelegate.notchWindowController?.expand(
                with: .notification(appName: appName, message: message, icon: icon)
            )
        }
    }
}

// MARK: - Legacy NSUserNotificationCenter delegate

class NotificationCenterDelegate: NSObject, NSUserNotificationCenterDelegate {

    static let shared = NotificationCenterDelegate()
    private override init() {}

    func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didDeliver notification: NSUserNotification
    ) {
        let appName = notification.subtitle ?? notification.title ?? "Notification"
        let message = notification.informativeText ?? notification.title ?? ""
        guard !message.isEmpty else { return }

        let icon: NSImage? = NSWorkspace.shared.icon(
            forFile: Bundle.main.bundlePath
        )

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.notchWindowController?.expand(
            with: .notification(appName: appName, message: message, icon: icon)
        )
    }

    // Allow notifications to be delivered even when app is in foreground
    func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        return true
    }
}
