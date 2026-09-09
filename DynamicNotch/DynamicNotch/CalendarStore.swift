import AppKit
import EventKit
import Observation

@Observable
final class CalendarStore {
    static let shared = CalendarStore()
    var selectedDate = Date() { didSet { refresh() } }
    private(set) var events: [EKEvent] = []
    private(set) var status = "Connect Calendar to see your events"
    private(set) var authorized = false
    private(set) var requesting = false
    private var activationObserver: NSObjectProtocol?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func connect() async {
        guard !requesting else { return }
        let permission = EKEventStore.authorizationStatus(for: .event)
        if permission == .denied || permission == .restricted {
            status = permission == .restricted ? "Calendar access is restricted on this Mac." : "Calendar access was denied. Enable DynamicNotch in Privacy & Security → Calendars."
            openPrivacy()
            return
        }
        requesting = true
        status = "Waiting for Calendar permission…"
        NSApp.activate(ignoringOtherApps: true)
        defer { requesting = false }
        do {
            let granted = try await store.requestFullAccessToEvents()
            refresh()
            if !granted { status = "Access not granted. Open Calendar privacy settings to enable DynamicNotch." }
        } catch { status = "Calendar permission failed: \(error.localizedDescription)" }
    }
    func openPrivacy() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }
    private func openSettings(_ address: String) {
        guard let url = URL(string: address) else { return }
        if !NSWorkspace.shared.open(url) {
            status = "Could not open System Settings. Open it manually from the Apple menu."
        }
    }
    func refresh() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard authorized else {
            events = []
            status = EKEventStore.authorizationStatus(for: .event) == .denied
                ? "Access denied. Enable DynamicNotch in Privacy & Security → Calendars."
                : "Connect your account in macOS, then allow this app to read its calendars."
            return
        }
        let start = Calendar.current.startOfDay(for: selectedDate)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
        status = events.isEmpty ? "No events on this day" : "\(events.count) events"
    }
    func openAccounts() {
        openSettings("x-apple.systempreferences:com.apple.preferences.internetaccounts")
    }
}
