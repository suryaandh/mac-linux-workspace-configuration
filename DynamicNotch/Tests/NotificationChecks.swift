import Foundation

@main
struct NotificationChecks {
    static func main() {
        let store = NotificationStore.shared
        store.clear()
        for index in 0..<105 { store.add(source: "Test", message: "Event \(index)") }
        precondition(store.items.count == 100)
        precondition(store.items.first?.message == "Event 104")
        precondition(store.items.last?.message == "Event 5")
        let id = store.items[0].id
        store.dismiss(id)
        precondition(store.items.count == 99 && !store.items.contains { $0.id == id })
        store.clear()
        precondition(store.items.isEmpty)
        print("Notification history checks passed")
    }
}
