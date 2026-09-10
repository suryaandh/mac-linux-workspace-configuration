import Foundation
import Observation

struct TodoItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var done = false
    var linkedTodoID: UUID?
    var parentID: UUID?
}
struct Memo: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled note"
    var body = ""
}
struct FocusSession: Identifiable, Codable {
    var id = UUID()
    var task: String
    var date = Date()
    var minutes: Int
    var todoID: UUID?
}

@Observable
final class ProductivityStore {
    static let shared = ProductivityStore()
    var todos: [TodoItem] { didSet { save(todos, key: "todos.v1"); syncLinkedFocus() } }
    var notes: [Memo] { didSet { save(notes, key: "notes.v1") } }
    var focusTasks: [TodoItem] { didSet { save(focusTasks, key: "focusTasks.v1") } }
    var sessions: [FocusSession] { didSet { save(sessions, key: "focusSessions.v1") } }
    var selectedNote: UUID?
    var selectedFocus: UUID?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        todos = Self.read("todos.v1", defaults: defaults) ?? []
        notes = Self.read("notes.v1", defaults: defaults) ?? []
        focusTasks = Self.read("focusTasks.v1", defaults: defaults) ?? []
        sessions = Self.read("focusSessions.v1", defaults: defaults) ?? []
        if defaults.data(forKey: "notes.v1") == nil, let legacy = defaults.string(forKey: "note"), !legacy.isEmpty {
            notes = [Memo(title: "Quick note", body: legacy)]
            save(notes, key: "notes.v1")
        }
        selectedNote = notes.first?.id
    }
    private static func read<T: Decodable>(_ key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    func addTodo(_ title: String, focus: Bool = false, parentID: UUID? = nil) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if focus { focusTasks.append(TodoItem(title: text)) }
        else {
            if let parentID { guard todos.contains(where: { $0.id == parentID && $0.parentID == nil && !$0.done }) else { return } }
            todos.append(TodoItem(title: text, parentID: parentID))
        }
    }
    func removeTodo(_ id: UUID) {
        todos.removeAll { $0.id == id || $0.parentID == id }
    }
    func setDone(_ id: UUID, _ done: Bool) {
        var updated = todos
        for index in updated.indices where updated[index].id == id || updated[index].parentID == id {
            updated[index].done = done
        }
        if !done, let parent = updated.first(where: { $0.id == id })?.parentID,
           let index = updated.firstIndex(where: { $0.id == parent }) { updated[index].done = false }
        todos = updated
    }
    func parentTitle(for todoID: UUID?) -> String? {
        guard let id = todoID, let parent = todos.first(where: { $0.id == id })?.parentID else { return nil }
        return todos.first(where: { $0.id == parent })?.title
    }
    func focusTitle(for task: TodoItem) -> String {
        guard let parent = parentTitle(for: task.linkedTodoID) else { return task.title }
        return "\(parent) › \(task.title)"
    }
    func focus(on todoID: UUID) {
        guard let todo = todos.first(where: { $0.id == todoID && !$0.done }) else { return }
        if let existing = focusTasks.first(where: { $0.linkedTodoID == todoID }) {
            selectedFocus = existing.id
        } else {
            let task = TodoItem(title: todo.title, linkedTodoID: todoID)
            focusTasks.append(task)
            selectedFocus = task.id
        }
    }
    private func syncLinkedFocus() {
        focusTasks = focusTasks.compactMap { task in
            guard let id = task.linkedTodoID else { return task }
            guard let todo = todos.first(where: { $0.id == id && !$0.done }) else { return nil }
            var updated = task
            updated.title = todo.title
            return updated
        }
        if !focusTasks.contains(where: { $0.id == selectedFocus }) { selectedFocus = nil }
    }
    func addNote() {
        let note = Memo()
        notes.insert(note, at: 0)
        selectedNote = note.id
    }
    func removeNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNote == id { selectedNote = notes.first?.id }
    }
    func completedFocus(task: String, minutes: Int, todoID: UUID? = nil) {
        sessions.insert(FocusSession(task: task, minutes: minutes, todoID: todoID), at: 0)
        if sessions.count > 200 { sessions.removeLast(sessions.count - 200) }
    }
    static func dayFraction(at date: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}
