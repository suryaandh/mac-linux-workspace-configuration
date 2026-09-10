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
        precondition(store.preview == nil)
        store.add(source: "Test", message: "Separate card")
        store.dismissPreview()
        precondition(store.preview == nil && store.items.count == 100)
        store.clear()
        precondition(store.items.isEmpty && store.preview == nil)
        precondition(NotificationIdentity.resolve("GPT")?.name == "ChatGPT")
        precondition(NotificationIdentity.resolve("INSTAGRAM (iPhone)")?.name == "Instagram")
        precondition(NotificationIdentity.resolve("com.apple.mirrored.com.mobile.ios.Tiket")?.name == "tiket.com")
        precondition(NotificationIdentity.resolve("remote:com.burbn.instagram")?.name == "Instagram")
        precondition(NotificationIdentity.resolve("https://instagram.com.evil.example") == nil)
        precondition(NotificationStore.parse("Mail\nSomeone mentioned Instagram\nChatGPT").source == "Mail")
        for source in ["DynamicNotch", "GPT", "Instagram", "TIKET.COM", "Telegram", "WhatsApp", "Gmail"] {
            store.add(source: source, message: "Icon check")
            precondition(store.items[0].appIcon != nil, "Missing bundled icon: \(source)")
        }
        store.clear()
        let telegram = NotificationStore.parse("Google Chrome\nhttps://web.telegram.org/k/\nAlice\nHello")
        precondition(telegram.source == "Telegram" && telegram.title == "Telegram")
        precondition(telegram.body == "Alice\nHello")
        precondition(NotificationStore.webAppName("https://web.telegram.org.evil.example") == nil)
        let native = NotificationStore.parse("Mail\nSubject\nMessage body")
        precondition(native.source == "Mail" && native.body == "Subject\nMessage body")
        store.add(source: "web.telegram.org", message: "Web Telegram")
        precondition(store.items[0].source == "Telegram" && store.items[0].appIcon != nil)
        store.clear()
        let message = "Google Chrome\nweb.telegram.org\nSame message"
        let now = Date()
        store.recordCaptured([message], now: now)
        store.recordCaptured([message], now: now.addingTimeInterval(2))
        precondition(store.items.count == 1, "Visible banner must not be duplicated")
        store.recordCaptured([], now: now.addingTimeInterval(3))
        store.recordCaptured([message], now: now.addingTimeInterval(4))
        precondition(store.items.count == 2, "Next identical notification must be accepted")
        store.recordCaptured([message, "Mail\nNew subject\nNew body"], now: now.addingTimeInterval(5))
        precondition(store.items.count == 3)
        precondition(store.dashboardItems.count == 3)
        precondition(NotificationStore.dashboardHeight(notificationCount: 0) == 150)
        precondition(NotificationStore.dashboardHeight(notificationCount: 1) == 253)
        precondition(NotificationStore.dashboardHeight(notificationCount: 3) == 389)
        precondition(NotificationStore.dashboardHeight(notificationCount: 100) == 389)
        store.dismiss(store.items[0].id)
        precondition(store.dashboardItems.count == 2)
        store.clear()
        print("Notification checks passed: identity, Telegram icon, repeated arrivals, dismissal, dashboard sizing")
    }
}
