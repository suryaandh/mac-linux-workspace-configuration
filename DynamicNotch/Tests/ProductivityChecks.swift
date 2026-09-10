import Foundation

@main struct ProductivityChecks {
    static func main() {
        let suite = "DynamicNotch.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Existing memo", forKey: "note")
        let store = ProductivityStore(defaults: defaults)
        precondition(store.notes.first?.body == "Existing memo")
        store.addTodo("   ")
        precondition(store.todos.isEmpty)
        store.addTodo(" Feature A ")
        store.todos[0].done = true
        store.addTodo("Feature B", focus: true)
        store.completedFocus(task: "Feature B", minutes: 25)
        store.removeNote(store.notes[0].id)
        let restored = ProductivityStore(defaults: defaults)
        precondition(restored.todos[0].title == "Feature A" && restored.todos[0].done)
        precondition(restored.focusTasks[0].title == "Feature B")
        precondition(restored.sessions[0].minutes == 25)
        precondition(restored.notes.isEmpty, "Deleted migrated notes must not return")
        restored.todos[0].done = false
        let todoID = restored.todos[0].id
        restored.focus(on: todoID)
        restored.focus(on: todoID)
        precondition(restored.focusTasks.filter { $0.linkedTodoID == todoID }.count == 1)
        restored.todos[0].title = "Renamed feature"
        precondition(restored.focusTasks.first { $0.linkedTodoID == todoID }?.title == "Renamed feature")
        restored.completedFocus(task: "Renamed feature", minutes: 25, todoID: todoID)
        precondition(restored.sessions[0].todoID == todoID)
        restored.todos[0].done = true
        precondition(!restored.focusTasks.contains { $0.linkedTodoID == todoID })
        precondition(restored.selectedFocus == nil)
        restored.addTodo("Project")
        let parentID = restored.todos.last!.id
        restored.addTodo("Child", parentID: parentID)
        let childID = restored.todos.last!.id
        restored.focus(on: childID)
        precondition(restored.focusTitle(for: restored.focusTasks.last!) == "Project › Child")
        let reloaded = ProductivityStore(defaults: defaults)
        precondition(reloaded.todos.last?.parentID == parentID)
        restored.setDone(parentID, true)
        precondition(restored.todos.first { $0.id == childID }!.done)
        precondition(!restored.focusTasks.contains { $0.linkedTodoID == childID })
        restored.setDone(childID, false)
        precondition(!restored.todos.first { $0.id == parentID }!.done)
        restored.focus(on: childID)
        restored.removeTodo(parentID)
        precondition(!restored.todos.contains { $0.id == childID || $0.id == parentID })
        precondition(!restored.focusTasks.contains { $0.linkedTodoID == childID })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        precondition(abs(ProductivityStore.dayFraction(at: middle, calendar: calendar) - 0.5) < 0.00001)
        precondition(ProductivityStore.dayFraction(at: start, calendar: calendar) == 0)
        print("Productivity checks passed: persistence, migration, focus history, DST day progress")
    }
}
