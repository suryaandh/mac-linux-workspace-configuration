import Cocoa

class NotchWindowController: NSWindowController {

    private var notchView: NotchView?

    convenience init() {
        guard let screen = NSScreen.main else {
            self.init(window: nil)
            return
        }

        let notchRect = NotchWindowController.notchFrame(for: screen)

        let window = NSWindow(
            contentRect: notchRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NotchView(frame: NSRect(origin: .zero, size: notchRect.size))
        window.contentView = view

        self.init(window: window)
        self.notchView = view

        window.orderFrontRegardless()
        let log = """
        window frame: \(window.frame)
        screen frame: \(screen.frame)
        notchRect: \(notchRect)
        """
        try? log.write(toFile: "/tmp/dynamicnotch.log", atomically: true, encoding: .utf8)
    }

    /// Returns the frame covering the physical notch area on the given screen.
    static func notchFrame(for screen: NSScreen) -> NSRect {
        let notchHeight: CGFloat
        if #available(macOS 12.0, *) {
            notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32
        } else {
            notchHeight = 32
        }

        let notchWidth: CGFloat = 220
        let screenFrame = screen.frame
        let x = screenFrame.midX - notchWidth / 2
        let y = screenFrame.maxY - notchHeight

        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    func expand(with content: NotchContent) {
        notchView?.expand(with: content)
    }

    func collapse() {
        notchView?.collapse()
    }
}
