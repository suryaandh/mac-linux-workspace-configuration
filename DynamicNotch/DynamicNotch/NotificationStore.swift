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
    private(set) var directCaptureReady = false
    var captureReady: Bool { directCaptureEnabled ? directCaptureReady : accessibilityGranted }
    private(set) var diagnostics = "No scan yet"
    private(set) var captureStatus = "Enable capture to receive app notifications"

    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var previewTask: Task<Void, Never>?
    private var recentMessages: [String: Date] = [:]
    private var visibleMessages = Set<String>()
    private var scanning = false
    private var timer: Timer?

    var preview: NotchNotification?

    var captureEnabled = UserDefaults.standard.bool(forKey: "captureNotifications") {
        didSet {
            UserDefaults.standard.set(captureEnabled, forKey: "captureNotifications")
            captureStatus = captureEnabled ? "Checking Accessibility access…" : "System capture is off"
            directCaptureReady = false
            database = NotificationDatabase()
            if captureEnabled { refreshPermission() }
        }
    }

    var dismissNativeBanners = UserDefaults.standard.object(forKey: "dismissNativeBanners") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(dismissNativeBanners, forKey: "dismissNativeBanners")
        }
    }

    // Direct mode does not rely on visible banners. macOS alert style must be
    // set to None separately while keeping notifications/Notification Center on.
    var directCaptureEnabled = UserDefaults.standard.object(forKey: "directNotificationCapture") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(directCaptureEnabled, forKey: "directNotificationCapture")
            directCaptureReady = false
            database = NotificationDatabase()
            nextDatabaseScan = .distantPast
            captureStatus = directCaptureEnabled ? "Checking direct notification access…" : "Accessibility capture selected"
        }
    }
    private var database = NotificationDatabase()
    private var nextDatabaseScan = Date.distantPast

    func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    func silenceNativeBanners() {
        switch NotificationSilencer.silenceAll() {
        case .success(let count):
            captureStatus = count > 0
                ? "Silenced \(count) apps • banners will not appear"
                : "All apps already set to no banner"
        case .failure(let error):
            captureStatus = error.localizedDescription
        }
    }

    func restoreNativeBanners() {
        switch NotificationSilencer.restore() {
        case .success(let count):
            captureStatus = count > 0 ? "Restored \(count) apps to original alert styles" : "Nothing to restore"
        case .failure(let error):
            captureStatus = error.localizedDescription
        }
    }

    var bannersSilenced: Bool { NotificationSilencer.hasBackup() }
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    private func scanDatabase() {
        guard !scanning, Date() >= nextDatabaseScan else { return }
        scanning = true
        nextDatabaseScan = Date().addingTimeInterval(0.35)
        let reader = database
        Task { [weak self] in
            guard let self else { return }
            defer { self.scanning = false }
            do {
                let batch = try await reader.poll()
                guard self.captureEnabled, self.directCaptureEnabled, self.database === reader else { return }
                for entry in batch.entries {
                    let identity = NotificationIdentity.resolve(entry.source)
                    let resolvedSource = identity?.name ?? entry.source
                    print("[DBEntry] source=\(entry.source) resolved=\(resolvedSource) title=\(entry.title) body=\(entry.body)")
                    // Browser: title=sender, body starts with domain then message content
                    if Self.isBrowser(resolvedSource) || Self.isBrowser(entry.source) {
                        let parsed = Self.parse(entry.body)
                        let sender = entry.title.isEmpty ? parsed.title : entry.title
                        self.add(source: parsed.source, message: parsed.body, displayName: sender)
                    } else if Self.isIPhoneMirroring(entry.source) {
                        // iPhone Mirroring: title=app name, body=message — use mirroring icon
                        let display = entry.title.isEmpty ? "iPhone" : entry.title
                        self.add(source: entry.source, message: entry.body, displayName: display)
                    } else {
                        let title = entry.title.isEmpty ? resolvedSource : entry.title
                        self.add(source: resolvedSource, message: entry.body, displayName: title)
                    }
                }
                self.directCaptureReady = true
                self.captureStatus = "Direct capture active • native alert style must be None"
                self.diagnostics = "\(batch.entries.count) new notifications; \(batch.skipped) unsupported records skipped"
            } catch {
                guard self.directCaptureEnabled, self.database === reader else { return }
                self.directCaptureReady = false
                self.captureStatus = error.localizedDescription
                self.nextDatabaseScan = Date().addingTimeInterval(2)
            }
        }
    }

    private init() {
        let polling = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.scan()
        }
        timer = polling
        RunLoop.main.add(polling, forMode: .common)
    }

    // MARK: - Helpers

    nonisolated static func webAppName(_ value: String) -> String? {
        NotificationIdentity.resolve(value)?.name
    }

    nonisolated static func isBrowser(_ value: String) -> Bool {
        let v = value.lowercased()
        let names = ["chrome", "google chrome", "safari", "firefox", "microsoft edge", "arc", "brave"]
        let bundles = ["com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
                       "com.microsoft.edgemac", "company.thebrowser.browser", "com.brave.browser"]
        return names.contains(v) || bundles.contains(v)
    }

    nonisolated static func isIPhoneMirroring(_ value: String) -> Bool {
        let v = value.lowercased()
        return v.contains("iphone-mirroring") || v.contains("iphonemirroring") ||
               v == "com.apple.iphone-mirroring" || v == "com.apple.continuity.iphone-mirroring"
    }

    nonisolated static func parse(_ message: String) -> (source: String, title: String, body: String) {
        let lines = message.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return ("Notification", "Notification", "") }

        let isBrowserSource = isBrowser(first)
        let isIPhone = ["iphone", "iphone mirroring", "notifications from iphone"].contains(first.lowercased())

        // Browser notification: line[0]=browser, line[1]=domain or sender, line[2+]=body
        if isBrowserSource, lines.count >= 2 {
            let second = lines[1]
            if let webApp = webAppName(second) {
                let sender = lines.count >= 3 ? lines[2] : webApp
                let body = lines.count >= 4 ? lines.dropFirst(3).joined(separator: "\n") : (lines.count == 3 ? lines[2] : second)
                return (webApp, sender, body)
            }
            let sender = second
            let body = lines.count >= 3 ? lines.dropFirst(2).joined(separator: "\n") : second
            return (first, sender, body)
        }

        // iPhone Mirroring: line[0]=iphone, line[1]=app name or domain
        if isIPhone, lines.count >= 2 {
            let second = lines[1]
            if let webApp = webAppName(second) {
                let sender = lines.count >= 3 ? lines[2] : webApp
                let body = lines.count >= 4 ? lines.dropFirst(3).joined(separator: "\n") : (lines.count == 3 ? lines[2] : second)
                return (webApp, sender, body)
            }
            let remaining = Array(lines.dropFirst(2))
            return (second, second, remaining.joined(separator: "\n"))
        }

        // Format: line[0]=sender, line[1]=web domain, line[2]=body
        // This covers notifications from the accessibility dump (e.g. Telegram/WA via notification center)
        if lines.count >= 2, let webApp = webAppName(lines[1]) {
            let sender = first
            let body = lines.count >= 3 ? lines[2] : webApp
            return (webApp, sender, body)
        }

        // Generic: line[0] is a known web-app
        if let webApp = webAppName(first) {
            let remaining = Array(lines.dropFirst())
            return (webApp, webApp, remaining.first ?? webApp)
        }

        return (first, first, lines.count > 1 ? lines[1] : first)
    }

    private static func icon(for appName: String) -> NSImage? {
        NotificationIdentity.icon(for: appName)
    }

    // MARK: - Public API

    // Strip bare web domain lines that leak into the displayed message
    private static func cleanMessage(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                guard line.contains("."), !line.contains(" ") else { return true }
                return URLComponents(string: "https://" + line)?.host == nil
            }
            .joined(separator: "\n")
    }

    var dashboardItems: [NotchNotification] {
        Array(items.prefix(3))
    }

    static func dashboardHeight(notificationCount: Int) -> CGFloat {
        let count = min(3, max(0, notificationCount))
        return 150 + (count == 0 ? 0 : 35 + CGFloat(count) * 68)
    }

    func add(source: String = "DynamicNotch", message: String, displayName: String? = nil) {
        let source = Self.webAppName(source) ?? source
        let cleaned = Self.cleanMessage(message)
        print("[Add] source=\(source) display=\(displayName ?? source) cleaned=\(cleaned)")
        let icon = Self.icon(for: source)
        let item = NotchNotification(
            source: source,
            displayName: displayName ?? source,
            message: cleaned,
            appIcon: icon
        )

        items.insert(item, at: 0)
        preview = item

        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            // Show immediately; auto-dismiss after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.preview = nil
        }

        if items.count > 100 {
            items.removeLast(items.count - 100)
        }
    }

    func dismissPreview() {
        previewTask?.cancel()
        preview = nil
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        if preview?.id == id {
            dismissPreview()
        }
    }

    func clear() {
        items.removeAll()
        preview = nil
        previewTask?.cancel()
    }

    func refreshPermission() {
        if directCaptureEnabled { nextDatabaseScan = .distantPast; scan(); return }
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            captureStatus = "Accessibility permission is not granted"
        }
        scan()
    }

    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestAccess() {
        if directCaptureEnabled { captureEnabled = true; openFullDiskAccess(); return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        accessibilityGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        captureEnabled = true

        if !accessibilityGranted {
            openPrivacy()
        }

        captureStatus = accessibilityGranted
            ? "Listening for visible app notifications"
            : "Allow DynamicNotch in System Settings → Privacy & Security → Accessibility"
    }

    // MARK: - AX Helpers

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    nonisolated private static func text(
        in element: AXUIElement,
        depth: Int = 0,
        budget: inout Int,
        deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.15
    ) -> [String] {
        guard depth < 12, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else {
            return []
        }
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

        // Fallback untuk group yang hanya punya description
        let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
        if result.isEmpty,
           (role == kAXGroupRole || role == "AXUnknown"),
           identifier.contains("notification") {
            if let description = attribute(element, kAXDescriptionAttribute) as? String, !description.isEmpty {
                result = [description]
            } else if let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty {
                result = [value]
            }
        }

        return result
    }

    // MARK: - Core Scan

    private func scan() {
        guard captureEnabled else {
            visibleMessages.removeAll()
            return
        }

        if directCaptureEnabled { scanDatabase(); return }
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else {
            captureStatus = "Accessibility access required — click Enable"
            return
        }

        captureStatus = "Listening • keep macOS banners enabled"

        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui"
        ).first else {
            captureStatus = "Waiting for macOS Notification Center"
            return
        }

        installObserver(pid: app.processIdentifier)

        guard !scanning else { return }
        scanning = true

        let pid = app.processIdentifier

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.readVisibleMessages(pid: pid)
            }.value

            guard let self else { return }
            defer { self.scanning = false }

            guard self.captureEnabled, !self.directCaptureEnabled else { return }

            self.diagnostics = "\(Date().formatted(date: .omitted, time: .standard)) • \(result.diagnostics)"

            guard let captured = result.messages else {
                self.captureStatus = "Cannot read Notification Center"
                return
            }

            self.recordCaptured(captured)

            if self.dismissNativeBanners && !result.banners.isEmpty {
                let outcome = await Task.detached(priority: .userInitiated) { Self.dismissBanners(result.banners) }.value
                self.captureStatus = outcome.dismissed == outcome.attempted
                    ? "Captured in notch • native close action succeeded"
                    : "Captured in notch • native banner could not be dismissed"
            }
        }
    }

    func recordCaptured(_ messages: [String], now: Date = Date()) {
        // Bersihkan cache lama (1 detik)
        recentMessages = recentMessages.filter { now.timeIntervalSince($0.value) < 1.0 }

        let current = Set(messages)

        for message in messages where !visibleMessages.contains(message) && recentMessages[message] == nil {
            print("[RawNotif] ===\n\(message)\n===")
            let entries = Self.splitNotifications(message)
            print("[Split] \(entries.count) entries from message")
            for entry in entries {
                print("[Entry] source=\(entry.source) title=\(entry.title) body=\(entry.body)")
                add(source: entry.source, message: entry.body, displayName: entry.title)
            }
            recentMessages[message] = now
        }

        visibleMessages = current
    }

    // Split a notification-center dump into individual notifications
    nonisolated static func splitNotifications(_ message: String) -> [(source: String, title: String, body: String)] {
        let lines = message.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        // Strategy 1: split by sender+domain pattern (line[i+1] is a known web domain)
        var domainCuts: [Int] = []
        for i in 0..<lines.count - 1 {
            if webAppName(lines[i + 1]) != nil { domainCuts.append(i) }
        }
        if !domainCuts.isEmpty {
            let start = domainCuts[0]
            let end = domainCuts.count > 1 ? domainCuts[1] : lines.count
            return [parse(lines[start..<end].joined(separator: "\n"))]
        }

        // Strategy 2: split by timestamp lines (e.g. "3m ago", "1h ago", "just now")
        let timestampRegex = try? NSRegularExpression(pattern: #"^\d+[smhd] ago$|^just now$|^now$"#, options: .caseInsensitive)
        func isTimestamp(_ s: String) -> Bool {
            guard let re = timestampRegex else { return false }
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }

        // Group lines into chunks: each chunk ends at a timestamp line
        var chunks: [ArraySlice<String>] = []
        var start = 0
        for i in 0..<lines.count {
            if isTimestamp(lines[i]) {
                if i > start { chunks.append(lines[start..<i]) }
                start = i + 1
            }
        }
        if start < lines.count { chunks.append(lines[start..<lines.count]) }

        guard !chunks.isEmpty else { return [parse(message)] }

        // Only return the first (most recent) chunk
        let first = chunks[0]
        guard first.count >= 1 else { return [] }
        let title = String(first[first.startIndex])
        let body = first.dropFirst().joined(separator: "\n")
        // Source unknown for HP notifications — use title as source so icon lookup can try
        return [(source: title, title: title, body: body.isEmpty ? title : body)]
    }

    private func installObserver(pid: pid_t) {
        guard observedPID != pid else { return }

        if let axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(axObserver),
                .commonModes
            )
        }

        axObserver = nil
        observedPID = nil

        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            DispatchQueue.main.async {
                NotificationStore.shared.scan()
            }
        }, &observer) == .success,
           let observer else { return }

        let root = AXUIElementCreateApplication(pid)

        for name in [
            kAXWindowCreatedNotification,
            kAXLayoutChangedNotification,
            kAXValueChangedNotification
        ] {
            _ = AXObserverAddNotification(observer, root, name as CFString, nil)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        axObserver = observer
        observedPID = pid
    }

    // MARK: - Banner Dismissal

    nonisolated private struct Banner: @unchecked Sendable {
        let element: AXUIElement
        let window: AXUIElement?
    }

    nonisolated private static func cancel(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success else {
            return false
        }

        let actionList = actions as? [String] ?? []

        // 1. Named close / cancel / dismiss
        for action in actionList {
            var description: CFString?
            _ = AXUIElementCopyActionDescription(element, action as CFString, &description)
            let label = (description as String? ?? "").lowercased()
            let actionLower = action.lowercased()

            let isClose = actionLower == kAXCancelAction.lowercased() ||
                          ["close", "dismiss"].contains(actionLower) ||
                          ["close", "dismiss", "tutup"].contains(label)

            if isClose {
                if AXUIElementPerformAction(element, action as CFString) == .success {
                    return true
                }
            }
        }

        return false
    }

    nonisolated private static func findAndPressCloseButton(
        in element: AXUIElement,
        depth: Int = 0,
        budget: inout Int,
        deadline: TimeInterval
    ) -> Bool {
        guard depth < 10, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else {
            return false
        }
        budget -= 1

        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
        let label = (
            (attribute(element, kAXTitleAttribute) as? String) ??
            (attribute(element, kAXDescriptionAttribute) as? String) ??
            ""
        ).lowercased()

        let closeLabels = [
            "close", "dismiss", "close notification",
            "dismiss notification", "tutup", "tutup pemberitahuan"
        ]
        let closeIDs = [
            "close", "closebutton", "dismissbutton",
            "notificationclosebutton", "notification-close-button"
        ]

        if role == kAXButtonRole,
           closeLabels.contains(label) || closeIDs.contains(identifier) {
            if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return true
            }
        }

        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if findAndPressCloseButton(in: child, depth: depth + 1, budget: &budget, deadline: deadline) {
                return true
            }
        }

        return false
    }

    // Fallback when dismissal fails: park the banner outside the visible screen.
    nonisolated private static func dismissBanners(_ banners: [Banner]) -> (attempted: Int, dismissed: Int) {
        var dismissed = 0

        for banner in banners {
            if cancel(banner.element) {
                dismissed += 1
                continue
            }

            var budget = 150
            let deadline = ProcessInfo.processInfo.systemUptime + 0.5

            if findAndPressCloseButton(in: banner.element, budget: &budget, deadline: deadline) {
                dismissed += 1
                continue
            }

            // Coba di level window
            if let window = banner.window, !CFEqual(window, banner.element) {
                if cancel(window) {
                    dismissed += 1
                    continue
                }
                if findAndPressCloseButton(in: window, budget: &budget, deadline: deadline) {
                    dismissed += 1
                    continue
                }
            }


        }

        return (banners.count, dismissed)
    }

    // MARK: - Read Messages

    nonisolated private static func notificationGroups(
        in element: AXUIElement,
        depth: Int = 0,
        budget: inout Int,
        deadline: TimeInterval
    ) -> [AXUIElement] {
        guard depth < 12, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else {
            return []
        }
        budget -= 1

        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()

        var groups: [AXUIElement] = []

        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            groups += notificationGroups(in: child, depth: depth + 1, budget: &budget, deadline: deadline)
        }

        if !groups.isEmpty { return groups }

        // Match by identifier first, then fall back to any group/unknown role at depth > 0
        if (role == kAXGroupRole || role == "AXUnknown"),
           !identifier.contains("center"),
           !identifier.contains("list") {
            if identifier.contains("notification") {
                return [element]
            }
        }

        return []
    }

    private struct ScanResult: Sendable {
        let messages: [String]?
        let diagnostics: String
        var banners: [Banner] = []
    }

    nonisolated private static func readVisibleMessages(pid: pid_t) -> ScanResult {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.06)

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value)
        let windows = value as? [AXUIElement] ?? []

        var roots: [AXUIElement] = windows

        if roots.isEmpty {
            roots = attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }

        if roots.isEmpty, let focused = attribute(root, kAXFocusedUIElementAttribute) {
            roots.append(focused as! AXUIElement)
        }

        if roots.isEmpty && error != .success && error != .noValue {
            return ScanResult(
                messages: nil,
                diagnostics: "AX error \(error.rawValue); windows: 0"
            )
        }

        var messages: [String] = []
        var banners: [Banner] = []
        var scanned = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35

        for element in roots.prefix(12) {
            if ProcessInfo.processInfo.systemUptime > deadline { break }

            var groupBudget = 120
            let groups = notificationGroups(in: element, budget: &groupBudget, deadline: deadline)

            guard groupBudget > 0, ProcessInfo.processInfo.systemUptime < deadline else { continue }

            // If no notification groups found, treat the window itself as the banner target
            let candidates: [AXUIElement] = groups.isEmpty ? [element] : groups
            let isWindowFallback = groups.isEmpty

            for candidate in candidates {
                var budget = 140
                let lines = text(in: candidate, budget: &budget, deadline: deadline)
                scanned += 140 - budget

                guard budget > 0, ProcessInfo.processInfo.systemUptime < deadline else { continue }

                if !lines.isEmpty {
                    let message = lines.joined(separator: "\n")
                    if !messages.contains(message) {
                        messages.append(message)
                    }
                    banners.append(Banner(
                        element: candidate,
                        window: (isWindowFallback || groups.count <= 1) ? element : nil
                    ))
                }
            }
        }

        return ScanResult(
            messages: messages,
            diagnostics: "windows: \(windows.count), roots: \(roots.count), elements: \(scanned), banners: \(banners.count), msgs: \(messages.count)",
            banners: banners
        )
    }
}
