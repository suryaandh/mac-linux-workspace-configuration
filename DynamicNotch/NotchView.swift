import Cocoa

enum NotchContent {
    case music(title: String, artist: String, artwork: NSImage?)
    case notification(appName: String, message: String, icon: NSImage?)
    case brightness
}

class NotchView: NSView {

    private let collapsedWidth: CGFloat = 220
    private let expandedWidth: CGFloat = 380
    private let collapsedHeight: CGFloat = 32
    private let expandedHeight: CGFloat = 80

    private var isExpanded = false
    private var collapseTimer: Timer?

    // Subviews
    private let backgroundView = NSView()
    private let musicView = MusicContentView()
    private let notifView = NotificationContentView()
    private let brightnessView = BrightnessContentView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.cgColor
        backgroundView.layer?.cornerRadius = 16
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        musicView.alphaValue = 0
        notifView.alphaValue = 0
        brightnessView.alphaValue = 0
        backgroundView.addSubview(musicView)
        backgroundView.addSubview(notifView)
        backgroundView.addSubview(brightnessView)
    }

    override func layout() {
        super.layout()
        if isExpanded {
            layoutExpanded()
        } else {
            layoutCollapsed()
        }
    }

    // MARK: - Layout

    private func layoutCollapsed() {
        // center horizontally in whatever the current window width is
        let w = bounds.width > 0 ? bounds.width : collapsedWidth
        let x = (w - collapsedWidth) / 2
        backgroundView.frame = NSRect(x: x, y: 0, width: collapsedWidth, height: collapsedHeight)
        musicView.frame = backgroundView.bounds
        notifView.frame = backgroundView.bounds
        brightnessView.frame = backgroundView.bounds
    }

    private func layoutExpanded() {
        // window is wider than expanded pill; center the pill inside it
        let w = bounds.width > 0 ? bounds.width : expandedWidth
        let x = (w - expandedWidth) / 2
        backgroundView.frame = NSRect(x: x, y: 0, width: expandedWidth, height: expandedHeight)
        musicView.frame = backgroundView.bounds
        notifView.frame = backgroundView.bounds
        brightnessView.frame = backgroundView.bounds
    }

    // MARK: - Public API

    override func mouseEntered(with event: NSEvent) {
        expand(with: .brightness)
    }

    override func mouseExited(with event: NSEvent) {
        collapse()
    }

    func expand(with content: NotchContent) {
        collapseTimer?.invalidate()
        isExpanded = true

        // fade out all content first, then resize, then show new content
        musicView.alphaValue = 0
        notifView.alphaValue = 0
        brightnessView.alphaValue = 0

        resizeWindow(to: NSSize(width: expandedWidth + 60, height: expandedHeight)) { [weak self] in
            guard let self = self else { return }
            // layout() will be called automatically as bounds update
            switch content {
            case .music(let title, let artist, let artwork):
                self.musicView.configure(title: title, artist: artist, artwork: artwork)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.musicView.animator().alphaValue = 1
                }
            case .notification(let appName, let message, let icon):
                self.notifView.configure(appName: appName, message: message, icon: icon)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.notifView.animator().alphaValue = 1
                }
            case .brightness:
                self.brightnessView.refresh()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.brightnessView.animator().alphaValue = 1
                }
            }
        }

        collapseTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        collapseTimer?.invalidate()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.musicView.animator().alphaValue = 0
            self.notifView.animator().alphaValue = 0
            self.brightnessView.animator().alphaValue = 0
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.layoutCollapsed()
                self.resizeWindow(to: NSSize(width: self.collapsedWidth, height: self.collapsedHeight))
            }
        }
    }

    private func resizeWindow(to size: NSSize, completion: (() -> Void)? = nil) {
        guard let window = self.window, let screen = NSScreen.main else { return }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        } completionHandler: {
            completion?()
        }
    }
}
