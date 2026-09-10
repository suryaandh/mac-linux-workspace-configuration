import AppKit
import ApplicationServices
import Observation

struct NotchNotification: Identifiable {
    let id = UUID()
    let source: String
    let displayName: String
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
    private var previewTask: Task<Void, Never>?
    private var recentMessages: [String: Date] = [:]
    var captureEnabled = UserDefaults.standard.bool(forKey: "captureNotifications") {
        didSet {
            UserDefaults.standard.set(captureEnabled, forKey: "captureNotifications")
            captureStatus = captureEnabled ? "Checking Accessibility access…" : "System capture is off"
        }
    }
    var dismissNativeBanners = UserDefaults.standard.object(forKey: "dismissNativeBanners") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dismissNativeBanners, forKey: "dismissNativeBanners") }
    }
    private var timer: Timer?
    private var visibleMessages = Set<String>()
    private var scanning = false

    private init() {
        let polling = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.scan() }
        timer = polling
        RunLoop.main.add(polling, forMode: .common)
    }

    private static func icon(for appName: String) -> NSImage? {
        let normalized = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Direct running app match
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").lowercased() == normalized || $0.bundleIdentifier?.lowercased() == normalized
        }) { return app.icon }
        // Known bundle aliases including web-origin sources routed through browsers
        let aliases: [String: String] = [
            "chrome": "com.google.Chrome",
            "google chrome": "com.google.Chrome",
            "whatsapp": "net.whatsapp.WhatsApp",
            "web.whatsapp.com": "net.whatsapp.WhatsApp",
            "telegram": "ru.keepcoder.Telegram",
            "telegram web": "ru.keepcoder.Telegram",
            "web.telegram.org": "ru.keepcoder.Telegram",
            "web.telegram.com": "ru.keepcoder.Telegram",
            "safari": "com.apple.Safari",
            "messages": "com.apple.MobileSMS",
            "mail": "com.apple.mail",
            "slack": "com.tinyspeck.slackmacgap",
            "notion": "notion.id",
            "linear": "com.linear",
            "discord": "com.hnc.Discord",
            "zoom": "us.zoom.xos",
        ]
        if let bundle = aliases[normalized], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        // Web notification via Chrome — source looks like a domain, fall back to Chrome icon
        if normalized.contains(".") && !normalized.contains(" "),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        // Fuzzy match against any running app whose name contains the source
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            guard let name = $0.localizedName else { return false }
            return name.lowercased().contains(normalized) || normalized.contains(name.lowercased())
        }) { return app.icon }
        return nil
    }

    func add(source: String = "DynamicNotch", message: String, displayName: String? = nil) {
        var icon = Self.icon(for: source)
        // Source may be a sender name; fall back to running browser
        if icon == nil {
            let browserBundles = ["com.google.Chrome", "com.apple.Safari",
                                  "org.mozilla.firefox", "com.microsoft.edgemac"]
            icon = browserBundles.compactMap { id in
                NSWorkspace.shared.runningApplications
                    .first(where: { $0.bundleIdentifier == id })?.icon
            }.first
        }
        let item = NotchNotification(source: source, displayName: displayName ?? source, message: message, appIcon: icon)
        items.insert(item, at: 0)
        preview = item
        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.preview = nil
        }
        if items.count > 100 { items.removeLast(items.count - 100) }
    }

    func dismissPreview() { previewTask?.cancel(); preview = nil }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        if preview?.id == id { dismissPreview() }
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
    nonisolated private static func text(in element: AXUIElement, depth: Int = 0, budget: inout Int, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.12) -> [String] {
        guard depth < 12, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else { return [] }
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
            result += text(in: child, depth: depth + 1, budget: &budget, deadline: deadline)
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
            var newlyCaptured = Set<String>()
            for message in captured {
                // Normalize to catch duplicates that differ only in whitespace/punctuation
                let key = message.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
                guard !self.visibleMessages.contains(message),
                      !self.recentMessages.keys.contains(where: {
                          $0.components(separatedBy: .whitespacesAndNewlines)
                              .filter { !$0.isEmpty }.joined(separator: " ").lowercased() == key
                      }) else { continue }
                let lines = message.components(separatedBy: "\n")
                let sourceLine = lines.count > 1 ? lines[0] : "Notification"
                let domainLine = lines.count > 2 ? lines[1] : nil
                let resolvedSource = domainLine ?? sourceLine
                // Skip domain line from message body so it doesn't show in preview
                let bodyLines = lines.count > 2 ? Array(lines.dropFirst(2)) : (lines.count > 1 ? Array(lines.dropFirst()) : lines)
                let body = bodyLines.joined(separator: "\n")
                self.add(source: resolvedSource, message: body, displayName: sourceLine)
                self.recentMessages[key] = Date()
                newlyCaptured.insert(message)
            }
            self.visibleMessages = Set(captured)
            if self.dismissNativeBanners, !newlyCaptured.isEmpty {
                let matching = newlyCaptured
                Task.detached(priority: .userInitiated) { Self.dismissBanners(pid: pid, matching: matching) }
            }
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

    // Only cancel an individual window whose complete text was just captured.
    // Never press arbitrary buttons or clear Notification Center history.
    nonisolated private static func dismissBanners(pid: pid_t, matching: Set<String>) {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.05)
        for window in attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            var budget = 120
            let deadline = ProcessInfo.processInfo.systemUptime + 0.12
            let groups = notificationGroups(in: window, budget: &budget, deadline: deadline)
            guard groups.count <= 1 else { continue }
            budget = 120
            let message = text(in: groups.first ?? window, budget: &budget, deadline: deadline).joined(separator: "\n")
            guard matching.contains(message) else { continue }
            // Move banner off-screen immediately to hide it before trying to cancel
            var offscreen = CGPoint(x: -9999, y: -9999)
            if let pos = AXValueCreate(.cgPoint, &offscreen) {
                _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
            }
            // Try Cancel action on window
            var actions: CFArray?
            if AXUIElementCopyActionNames(window, &actions) == .success,
               (actions as? [String] ?? []).contains(kAXCancelAction) {
                _ = AXUIElementPerformAction(window, kAXCancelAction as CFString)
                continue
            }
            // Fall back: find and press a close/dismiss button inside the window
            if let dismissed = findAndPressCloseButton(in: window) { _ = dismissed; continue }
            // Last resort: try Cancel on the notification group itself
            if let group = groups.first {
                var groupActions: CFArray?
                if AXUIElementCopyActionNames(group, &groupActions) == .success,
                   (groupActions as? [String] ?? []).contains(kAXCancelAction) {
                    _ = AXUIElementPerformAction(group, kAXCancelAction as CFString)
                }
            }
        }
    }

    nonisolated private static func findAndPressCloseButton(in element: AXUIElement, depth: Int = 0) -> Bool? {
        guard depth < 8 else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
        let label = ((attribute(element, kAXTitleAttribute) as? String) ?? (attribute(element, kAXDescriptionAttribute) as? String) ?? "").lowercased()
        // Match close/dismiss buttons by role + label or identifier
        if role == kAXButtonRole, ["close", "dismiss", "cancel"].contains(where: { label.contains($0) || identifier.contains($0) }) {
            _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
            return true
        }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let found = findAndPressCloseButton(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    // Prefer individual notification groups to a whole-window snapshot. Reading
    // the containing window would combine unrelated or previously closed cards.
    nonisolated private static func notificationGroups(in element: AXUIElement, depth: Int = 0,
                                                       budget: inout Int, deadline: TimeInterval) -> [AXUIElement] {
        guard depth < 12, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else { return [] }
        budget -= 1
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
        var groups: [AXUIElement] = []
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            groups += notificationGroups(in: child, depth: depth + 1, budget: &budget, deadline: deadline)
        }
        if !groups.isEmpty { return groups }
        if (role == kAXGroupRole || role == "AXUnknown"), identifier.contains("notification"),
           !identifier.contains("center"), !identifier.contains("list") { return [element] }
        return []
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
        if roots.isEmpty, let focused = attribute(root, kAXFocusedUIElementAttribute) {
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
            var groupBudget = 100
            let groups = notificationGroups(in: element, budget: &groupBudget, deadline: deadline)
            // A focused child must not produce a second partial copy of a window.
            if groups.isEmpty && !windows.contains(where: { CFEqual($0, element) }) { continue }
            for candidate in groups.isEmpty ? [element] : groups {
                var budget = 120
                let lines = text(in: candidate, budget: &budget, deadline: deadline)
                scanned += 120 - budget
                guard budget > 0, ProcessInfo.processInfo.systemUptime < deadline else { continue }
                if !lines.isEmpty {
                    let message = lines.joined(separator: "\n")
                    if !messages.contains(message) { messages.append(message) }
                }
            }
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
