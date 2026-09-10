import SwiftUI
import EventKit

struct DashboardView: View {
    private var store = ProductivityStore.shared
    private var timer = ActivityStore.shared
    private var media = MediaRemoteManager.shared
    var body: some View {
        HStack(spacing: 0) {
            section("TODO", tab: "todo") {
                Text("\(store.todos.filter { !$0.done }.count) remaining").font(.system(size: 14, weight: .semibold))
                Text(store.todos.first(where: { !$0.done })?.title ?? "All clear").lineLimit(1).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 5) {
                Button("NOW PLAYING") { timer.selected = "music" }.font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Text(media.title.isEmpty ? "Nothing playing" : media.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack {
                    Text(media.artist).lineLimit(1).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Button { media.togglePlayPause() } label: { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel("Play or pause")
                }
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
            Divider().padding(.vertical, 4)
            section("POMODORO", tab: "timer") {
                Text(timer.timerActive ? timer.timeLabel : String(format: "%02d:00", UserDefaults.standard.object(forKey: "focusMinutes") as? Int ?? 25)).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                Text(timer.timerActive ? timer.focusTitle : "Ready to focus").lineLimit(1).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                section("DAY PROGRESS", tab: "day") {
                    Text("\(Int(ProductivityStore.dayFraction(at: context.date) * 100))%")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                    ProgressView(value: ProductivityStore.dayFraction(at: context.date)).tint(.mint)
                }
            }
        }.font(.system(size: 10)).frame(maxHeight: .infinity)
    }
    private func section<C: View>(_ title: String, tab: String, @ViewBuilder content: () -> C) -> some View {
        Button { timer.selected = tab } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
        }
    }
}

struct TodoView: View {
    @Bindable private var store = ProductivityStore.shared
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("What needs to get done?", text: $draft).onSubmit(add)
                Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if store.todos.isEmpty { Text("A clear list. Add your first task above.").foregroundStyle(.secondary) }
                    ForEach(store.todos.filter { $0.parentID == nil }) { todo in
                        TodoCard(todo: todo)
                    }
                }
            }
            Text("\(store.todos.filter(\.done).count) of \(store.todos.count) completed").font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 12))
    }
    private func add() { store.addTodo(draft); draft = "" }
}

private struct TodoCard: View {
    let todo: TodoItem
    private var store = ProductivityStore.shared
    @State private var childDraft = ""
    init(todo: TodoItem) { self.todo = todo }
    private var children: [TodoItem] { store.todos.filter { $0.parentID == todo.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(todo)
            if !children.isEmpty {
                HStack {
                    Text("SUBTASKS").tracking(1)
                    Spacer()
                    Text("\(children.filter(\.done).count)/\(children.count)")
                }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(children) { child in row(child).padding(.leading, 12) }
                ProgressView(value: Double(children.filter(\.done).count), total: Double(children.count)).tint(.mint)
            }
            if !todo.done {
                HStack {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    TextField("Add a subtask…", text: $childDraft).onSubmit(addChild)
                    Button(action: addChild) { Image(systemName: "plus.circle.fill").foregroundStyle(.mint) }
                        .disabled(childDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Add subtask")
                }.font(.system(size: 11))
            }
        }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }
    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 9) {
            Button { store.setDone(item.id, !item.done) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? .mint : .gray)
            }.help(item.done ? "Mark incomplete" : "Complete task")
            TextField("Task", text: Binding(get: {
                store.todos.first { $0.id == item.id }?.title ?? ""
            }, set: { title in
                if let index = store.todos.firstIndex(where: { $0.id == item.id }) { store.todos[index].title = title }
            })).textFieldStyle(.plain).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
            Button { store.focus(on: item.id); ActivityStore.shared.selected = "timer" } label: {
                Image(systemName: "timer").foregroundStyle(.mint)
            }.disabled(item.done).help("Add to Pomodoro")
            Button { store.removeTodo(item.id) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                .help(item.parentID == nil ? "Delete task and its subtasks" : "Delete subtask")
        }
    }
    private func addChild() { store.addTodo(childDraft, parentID: todo.id); childDraft = "" }
}

struct NotesView: View {
    @Bindable private var store = ProductivityStore.shared
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Button { store.addNote() } label: { Label("New note", systemImage: "square.and.pencil") }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(store.notes) { note in
                            Button { store.selectedNote = note.id } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title.isEmpty ? "Untitled note" : note.title).fontWeight(.medium).lineLimit(1)
                                    Text(note.body.isEmpty ? "Start writing…" : note.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    .background(store.selectedNote == note.id ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }.frame(width: 170)
            Divider()
            if let id = store.selectedNote, store.notes.contains(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Note title", text: binding(id, \.title)).font(.headline).textFieldStyle(.plain)
                        Button { store.removeNote(id) } label: { Image(systemName: "trash") }.help("Delete note")
                    }
                    TextEditor(text: binding(id, \.body)).scrollContentBackground(.hidden)
                        .padding(6).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    Text("Saved automatically on this Mac").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Your notes", systemImage: "note.text", description: Text("Create a note to start writing."))
            }
        }.font(.system(size: 12))
    }
    private func binding(_ id: UUID, _ key: WritableKeyPath<Memo, String>) -> Binding<String> {
        Binding(get: { store.notes.first { $0.id == id }?[keyPath: key] ?? "" }, set: { value in
            if let index = store.notes.firstIndex(where: { $0.id == id }) { store.notes[index][keyPath: key] = value }
        })
    }
}

struct PomodoroView: View {
    @Bindable private var store = ProductivityStore.shared
    private var timer = ActivityStore.shared
    @State private var draft = ""
    @AppStorage("focusMinutes") private var minutes = 25
    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 7)
                    Circle().trim(from: 0, to: timer.total > 0 ? timer.remaining / timer.total : 1)
                        .stroke(.mint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(timer.timerActive ? timer.timeLabel : String(format: "%02d:00", minutes))
                            .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(timer.timerActive ? timer.focusTitle : "Ready to focus").font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    }.padding(16)
                }.frame(width: 130, height: 130)
                if timer.timerActive {
                    HStack { Button(timer.running ? "Pause" : "Resume") { timer.toggleTimer() }; Button("Stop") { timer.stop() } }
                } else {
                    HStack(spacing: 8) {
                        ForEach([5, 15, 25, 50], id: \.self) { value in
                            Button("\(value)") { minutes = value }.foregroundStyle(minutes == value ? .mint : .white)
                        }
                    }
                    HStack {
                        Text("Minutes")
                        TextField("1–240", value: $minutes, format: .number).frame(width: 48)
                        Stepper("Minutes", value: $minutes, in: 1...240).labelsHidden()
                    }.font(.caption)
                    Button("Start focus") {
                        let selected = store.focusTasks.first { $0.id == store.selectedFocus }
                        timer.start(minutes: minutes, task: selected.map { store.focusTitle(for: $0) } ?? "Focus", todoID: selected?.linkedTodoID)
                    }.buttonStyle(.borderedProminent).tint(.mint).disabled(!(1...240).contains(minutes))
                }
            }.frame(width: 185)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("FOCUS QUEUE").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Feature A, feature B…", text: $draft).onSubmit(add)
                    Button("Add", action: add)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.focusTasks) { task in
                            HStack {
                                Button { store.selectedFocus = task.id } label: {
                                    Label(store.focusTitle(for: task), systemImage: task.linkedTodoID != nil ? "checklist" : (store.selectedFocus == task.id ? "record.circle.fill" : "circle"))
                                        .foregroundStyle(store.selectedFocus == task.id ? .mint : .white)
                                }
                                Spacer()
                                Button {
                                    store.focusTasks.removeAll { $0.id == task.id }
                                    if store.selectedFocus == task.id { store.selectedFocus = nil }
                                } label: { Image(systemName: "xmark") }
                            }.padding(6)
                        }
                        if store.focusTasks.isEmpty { Text("Add a task, select it, then start a session.").foregroundStyle(.secondary) }
                        Divider()
                        Text("COMPLETED SESSIONS").font(.caption).foregroundStyle(.secondary)
                        ForEach(store.sessions.prefix(20)) { session in
                            HStack { Text(session.task).lineLimit(1); Spacer(); Text("\(session.minutes)m"); Text(session.date, style: .date) }.font(.caption)
                        }
                    }
                }
            }
        }.font(.system(size: 12))
    }
    private func add() { store.addTodo(draft, focus: true); draft = "" }
}

struct DayProgressView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let progress = ProductivityStore.dayFraction(at: context.date)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.date, format: .dateTime.weekday(.wide).month().day()).font(.title3)
                        Text("Make room for what matters today.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(progress * 100))% ").font(.system(size: 36, weight: .light, design: .rounded))
                }
                ProgressView(value: progress).tint(.mint)
                HStack { Text("Midnight"); Spacer(); Text("Noon"); Spacer(); Text("Midnight") }.font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Label("\(ProductivityStore.shared.todos.filter { !$0.done }.count) tasks left", systemImage: "checkmark.circle")
                    Spacer()
                    Label("\(ProductivityStore.shared.sessions.filter { Calendar.current.isDateInToday($0.date) }.count) focus sessions today", systemImage: "timer")
                }.font(.caption)
            }.padding(12)
        }
    }
}
