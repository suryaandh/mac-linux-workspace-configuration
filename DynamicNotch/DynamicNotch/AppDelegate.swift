import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notchController = NotchWindowController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notchController.show()
        _ = ClipboardStore.shared
        _ = NotificationStore.shared
        _ = ActivityStore.shared
        _ = MediaRemoteManager.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "DynamicNotch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open DynamicNotch", action: #selector(expand), keyEquivalent: "")
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DynamicNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.first?.target = self
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaRemoteManager.shared.stop()
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func expand() { NotchState.shared.isExpanded = true }
}
