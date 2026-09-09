import Foundation

// Standalone checks compiled with the production ActivityStore.
final class NotchState {
    static let shared = NotchState()
    var isExpanded = false
}

@main
struct TimerChecks {
    static func main() {
        let store = ActivityStore.shared
        store.start(minutes: 25)
        precondition(store.remaining == 1500 && store.running)
        let deadline = store.deadline!
        store.tick(now: deadline.addingTimeInterval(-60))
        precondition(store.remaining == 60 && store.timeLabel == "01:00")
        store.stop()
        precondition(!store.running && !store.timerActive && store.total == 0)
        store.start(minutes: 5)
        store.toggleTimer()
        let paused = store.remaining
        store.tick(now: Date().addingTimeInterval(1000))
        precondition(!store.running && store.remaining == paused)
        store.toggleTimer()
        precondition(store.running && store.deadline != nil)
        store.stop()
        precondition(!store.accept([URL(string: "https://example.com/file")!]))
        print("Timer and file validation checks passed")
    }
}
