import AppKit
import Observation

@Observable
final class ActivityStore {
    static let shared = ActivityStore()
    var selected = "dashboard"
    var files: [URL] = []
    var alert: String?
    var remaining: TimeInterval = 0
    var total: TimeInterval = 0
    var deadline: Date?
    private(set) var focusTitle = "Focus"
    private var focusTodoID: UUID?
    private var ticker: Timer?
    private var alertTask: Task<Void, Never>?

    var running: Bool { deadline != nil }
    var timerActive: Bool { remaining > 0 }
    var timeLabel: String {
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private init() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func start(minutes: Int, task: String = "Focus", todoID: UUID? = nil) {
        focusTitle = task
        focusTodoID = todoID
        total = Double(minutes * 60)
        remaining = total
        deadline = Date().addingTimeInterval(total)
    }

    func tick(now: Date = Date()) {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now))
        if remaining == 0 {
            self.deadline = nil
            ProductivityStore.shared.completedFocus(task: focusTitle, minutes: Int(total / 60), todoID: focusTodoID)
            NSSound.beep()
            notify("Timer selesai / Timer finished")
        }
    }

    func toggleTimer() {
        if running { tick(); deadline = nil }
        else if remaining > 0 { deadline = Date().addingTimeInterval(remaining) }
    }

    func stop() { deadline = nil; remaining = 0; total = 0 }

    func notify(_ message: String) {
        NotificationStore.shared.add(message: message)
        alertTask?.cancel()
        alert = message
        alertTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            alert = nil
        }
    }

    func accept(_ urls: [URL]) -> Bool {
        let accepted = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        guard !accepted.isEmpty else { return false }
        files = Array(Set(files + accepted)).sorted { $0.path < $1.path }
        selected = "files"
        NotchState.shared.isExpanded = true
        return true
    }

    func copyFiles() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects(files as [NSURL]) { notify("Files copied") }
    }
}
