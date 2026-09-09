import AppKit
import SwiftUI
import Observation

@Observable
final class NotchState {
    static let shared = NotchState()
    var isExpanded = false
    var collapsedSize = CGSize(width: 170, height: 24)
    var isDropTargeted = false
    var hasPhysicalNotch = false
    var revealProgress: CGFloat = 0
    var renderedPage = "dashboard"
    var contentOpacity: Double = 1
    var presentationSize = CGSize(width: 170, height: 24)
    var targetSize: CGSize {
        if isExpanded { return Self.pageSize }
        if NotificationStore.shared.preview != nil { return Self.previewSize }
        return collapsedSize
    }
    static let previewSize = CGSize(width: 460, height: 96)
    static let expandedSize = CGSize(width: 640, height: 330)
    static var pageSize: CGSize { size(for: ActivityStore.shared.selected) }
    static func size(for page: String) -> CGSize {
        page == "dashboard" ? CGSize(width: 640, height: 150) : expandedSize
    }
}

private final class NotchNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchWindowController {
    private var window: NotchNSWindow?
    private var screenObserver: NSObjectProtocol?
    private var hoverTimer: Timer?
    private var outsideSince: Date?
    private var animationTimer: Timer?
    private var suppressHoverUntilExit = false

    private func notchRect(on screen: NSScreen) -> CGRect {
        NotchGeometry.collapsedRect(screen: screen.frame, left: screen.auxiliaryTopLeftArea,
                                    right: screen.auxiliaryTopRightArea, topInset: screen.safeAreaInsets.top)
    }

    func show() {
        guard window == nil, let screen = NSScreen.main else { return }
        let notch = notchRect(on: screen)
        NotchState.shared.collapsedSize = notch.size
        NotchState.shared.presentationSize = notch.size
        NotchState.shared.hasPhysicalNotch = screen.safeAreaInsets.top > 0
        let window = NotchNSWindow(
            contentRect: notch,
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: NotchView())
        self.window = window
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resize()
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.updateHover()
        }
        observeExpansion()
        window.orderFrontRegardless()
    }

    private func observeExpansion() {
        withObservationTracking {
            _ = NotchState.shared.isExpanded
            _ = NotificationStore.shared.preview?.id
            _ = ActivityStore.shared.selected
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.animateExpansion()
                self?.observeExpansion()
            }
        }
    }

    private func resize() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let state = NotchState.shared
        let notch = notchRect(on: screen)
        state.collapsedSize = notch.size
        state.hasPhysicalNotch = screen.safeAreaInsets.top > 0
        // Use presentationSize height so window tracks the animation rather than snapping
        let h = max(notch.size.height, state.presentationSize.height)
        let w = state.revealProgress > 0 || NotificationStore.shared.preview != nil
            ? NotchState.expandedSize.width + 32
            : notch.size.width
        let size = CGSize(width: w, height: h)
        window.setFrame(NSRect(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height,
                               width: size.width, height: size.height), display: true)
    }

    private func animateExpansion() {
        animationTimer?.invalidate()
        let state = NotchState.shared
        let start = state.revealProgress
        let target: CGFloat = state.isExpanded || NotificationStore.shared.preview != nil ? 1 : 0
        let destinationPage = ActivityStore.shared.selected
        let pageChanged = state.renderedPage != destinationPage
        let initialOpacity = state.contentOpacity
        let startSize = state.presentationSize
        let endSize = state.targetSize
        if !state.isExpanded { suppressHoverUntilExit = true }
        // Page-only switch: detect before resize so we can skip the initial snap
        let pageOnlySwitch = pageChanged && state.isExpanded && start >= 0.99
        if !pageOnlySwitch { resize() }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            state.revealProgress = target
            state.presentationSize = endSize
            state.renderedPage = destinationPage
            state.contentOpacity = 1
            resize()
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        let duration = pageOnlySwitch ? 0.32 : 0.5
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let t = min(1, elapsed / duration)
            let eased = t * t * t * (t * (6 * t - 15) + 10)
            let animH = startSize.height + (endSize.height - startSize.height) * eased
            let animW = startSize.width + (endSize.width - startSize.width) * eased
            if pageChanged {
                let fadeDuration = pageOnlySwitch ? 0.08 : 0.10
                let fadeIn = pageOnlySwitch ? 0.12 : 0.30
                if elapsed < fadeDuration {
                    state.contentOpacity = initialOpacity * (1 - elapsed / fadeDuration)
                } else {
                    // For growing switches (e.g. dashboard→page), wait until height reaches 70% before revealing
                    let growing = pageOnlySwitch && endSize.height > startSize.height + 8
                    let heightReady = !growing || animH >= startSize.height + (endSize.height - startSize.height) * 0.7
                    if heightReady { state.renderedPage = destinationPage }
                    state.contentOpacity = heightReady ? min(1, (elapsed - fadeDuration) / fadeIn) : 0
                }
            }
            if !pageOnlySwitch {
                state.revealProgress = start + (target - start) * eased
            }
            state.presentationSize = CGSize(width: animW, height: animH)
            // Drive window frame directly so it grows/shrinks with the animation
            if let win = self?.window, let screen = win.screen ?? NSScreen.main {
                let notch = self?.notchRect(on: screen) ?? .zero
                let w = NotchState.expandedSize.width + 32
                win.setFrame(NSRect(x: notch.midX - w / 2, y: screen.frame.maxY - animH, width: w, height: animH), display: false)
            }
            if t >= 1 { timer.invalidate(); self?.animationTimer = nil; self?.resize() }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateHover() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let state = NotchState.shared
        let pointer = NSEvent.mouseLocation
        // Only the actual camera cutout opens the panel. No padded SwiftUI hover region.
        if !state.isExpanded && NotificationStore.shared.preview == nil {
            outsideSince = nil
            let inside = notchRect(on: screen).contains(pointer)
            if !inside { suppressHoverUntilExit = false }
            window.ignoresMouseEvents = !inside
            if inside && !suppressHoverUntilExit { state.isExpanded = true }
            return
        }
        let point = CGPoint(x: pointer.x - window.frame.midX + state.presentationSize.width / 2,
                            y: window.frame.maxY - pointer.y)
        let radius = UserDefaults.standard.object(forKey: "notchRadius") as? Double ?? 24
        let inside = NotchShape(bottomRadius: 8 + (radius - 8) * state.revealProgress,
                                topRadius: 16 * state.revealProgress)
            .path(in: CGRect(origin: .zero, size: state.presentationSize)).contains(point)
        window.ignoresMouseEvents = !inside && !state.isDropTargeted
        if animationTimer != nil { outsideSince = nil; return }
        if !state.isExpanded {
            let onNotch = notchRect(on: screen).contains(pointer)
            if onNotch && !suppressHoverUntilExit { state.isExpanded = true }
            if !onNotch { suppressHoverUntilExit = false }
            return
        }
        if inside || state.isDropTargeted {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.18 { state.isExpanded = false; outsideSince = nil }
        } else { outsideSince = Date() }
    }

}
