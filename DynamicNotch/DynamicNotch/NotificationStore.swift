import AppKit
import ApplicationServices
import Observation

struct NotchNotification: Identifiable {
    let id = UUID()
    let source: String
    let message: String
    let date = Date()
    let appIcon: NSImage?
}

@Observable
final class NotificationStore {
    static let shared = NotificationStore()
    private(set) var items: [NotchNotification] = []
    private(set) var accessibilityGranted = false
    private(set) var diagnostics = "No scan yet"
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private(set) var captureStatus = "Enable capture to receive app notifications"
    var preview: NotchNotification?
    private(set) var lastPreview: NotchNotification?
    private var previewTask: Task<Void, Never>?
    private var recentMessages: [String: Date] = [:]
    var captureEnabled = UserDefaults.standard.bool(forKey: "captureNotifications") {
        didSet {
            UserDefaults.standard.set(captureEnabled, forKey: "captureNotifications")
            captureStatus = captureEnabled ? "Checking Accessibility access…" : "System capture is off"
        }
    }
    private var timer: Timer?
    private var visibleMessages = Set<String>()
    private var scanning = false

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.scan() }
    }

    private static func icon(for appName: String) -> NSImage? {
        let normalized = appName.lowercased()
        return NSWorkspace.shared.runningApplications.first {
            ($0.localizedName ?? "").lowercased() == normalized
        }?.icon
    }

    func add(source: String = "DynamicNotch", message: String) {
        let icon = Self.icon(for: source)
        let item = NotchNotification(source: source, message: message, appIcon: icon)
        items.insert(item, at: 0)
        preview = item
        lastPreview = item
        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.preview = nil
        }
        if items.count > 100 { items.removeLast(items.count - 100) }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        if preview?.id == id { preview = nil }
    }
    func clear() { items.removeAll(); preview = nil; previewTask?.cancel() }

    func refreshPermission() {
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted { captureStatus = "Accessibility permission is not granted to this build" }
        scan()
    }
    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        accessibilityGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        captureEnabled = true
        if !accessibilityGranted { openPrivacy() }
        captureStatus = accessibilityGranted ? "Listening for visible app notifications" : "Allow DynamicNotch in System Settings → Privacy & Security → Accessibility"
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    // Read only text exposed by Notification Center. Do not inspect other apps,
    // private notification databases, or attempt to reveal hidden previews.
    nonisolated private static func text(in element: AXUIElement, depth: Int = 0, budget: inout Int) -> [String] {
        guard depth < 12, budget > 0 else { return [] }
        budget -= 1
        var result: [String] = []
        let role = attribute(element, kAXRoleAttribute) as? String
        if role == kAXStaticTextRole {
            for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let value = attribute(element, key) as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(value)
                    break
                }
            }
        }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            result += text(in: child, depth: depth + 1, budget: &budget)
        }
        // Some macOS banner versions expose the entire message as a group
        // description instead of static-text children. Only use it if no leaf
        // text was available and the element is identified as a notification.
        let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
        if result.isEmpty, role == kAXGroupRole || role == "AXUnknown", identifier.contains("notification") {
            if let description = attribute(element, kAXDescriptionAttribute) as? String, !description.isEmpty {
                result = [description]
            } else if let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty {
                result = [value]
            }
        }
        return result
    }

    private func scan() {
        guard captureEnabled else { visibleMessages.removeAll(); return }
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else {
            captureStatus = "Accessibility access required — click Enable in this tab"
            return
        }
        captureStatus = "Listening • keep macOS banners enabled"
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            captureStatus = "Waiting for macOS Notification Center"
            return
        }
        installObserver(pid: app.processIdentifier)
        guard !scanning else { return }
        scanning = true
        let pid = app.processIdentifier
        Task { [weak self] in
            let messages = await Task.detached(priority: .userInitiated) { Self.readVisibleMessages(pid: pid) }.value
            guard let self else {
                // Prevent scanning from being permanently stuck if self is deallocated
                return
            }
            self.scanning = false
            guard self.captureEnabled else { return }
            self.diagnostics = "\(Date().formatted(date: .omitted, time: .standard)) • " + messages.diagnostics
            guard let captured = messages.messages else {
                self.captureStatus = "Cannot read Notification Center — check Accessibility access"
                return
            }
            self.recentMessages = self.recentMessages.filter { Date().timeIntervalSince($0.value) < 300 }
            for message in captured where !self.visibleMessages.contains(message) && self.recentMessages[message] == nil {
                let lines = message.components(separatedBy: "\n")
                self.add(source: lines.count > 1 ? lines[0] : "Notification", message: lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : message)
                self.recentMessages[message] = Date()
            }
            self.visibleMessages = Set(captured)
        }
    }

    private func installObserver(pid: pid_t) {
        guard observedPID != pid else { return }
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        axObserver = nil
        observedPID = nil
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            DispatchQueue.main.async { NotificationStore.shared.scan() }
        }, &observer) == .success, let observer else { return }
        let root = AXUIElementCreateApplication(pid)
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXValueChangedNotification] {
            _ = AXObserverAddNotification(observer, root, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        observedPID = pid
    }

    private struct ScanResult: Sendable {
        let messages: [String]?
        let diagnostics: String
    }
    nonisolated private static func readVisibleMessages(pid: pid_t) -> ScanResult {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.05)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value)
        let windows = value as? [AXUIElement] ?? []

        // Build candidate roots: windows first, then children, then focused element
        var roots: [AXUIElement] = windows
        if roots.isEmpty {
            roots = attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        // Also probe focused UI element in case banner is a floating overlay
        if let focused = attribute(root, kAXFocusedUIElementAttribute) {
            roots.append(focused as! AXUIElement)
        }

        if roots.isEmpty && error != .success && error != .noValue {
            return ScanResult(messages: nil, diagnostics: "AX error \(error.rawValue); windows: 0; Accessibility must be enabled for the running app")
        }
        var messages: [String] = []
        var scanned = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        for element in roots.prefix(10) {
            if ProcessInfo.processInfo.systemUptime > deadline { break }
            var budget = 120
            let lines = text(in: element, budget: &budget)
            scanned += 180 - budget
            if !lines.isEmpty { messages.append(lines.joined(separator: "\n")) }
        }

        // Debug: log available attribute names on root when nothing found
        var attrNamesRef: CFArray?
        let attrList: String
        if messages.isEmpty, AXUIElementCopyAttributeNames(root, &attrNamesRef) == .success,
           let names = attrNamesRef as? [String] {
            attrList = names.joined(separator: ",")
        } else {
            attrList = ""
        }

        return ScanResult(messages: messages, diagnostics: "windows: \(windows.count), roots: \(roots.count), elements: \(scanned), readable banners: \(messages.count)\(attrList.isEmpty ? "" : " | attrs: \(attrList)")")
    }
}
