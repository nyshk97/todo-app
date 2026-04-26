import Foundation
import SwiftData
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class TodoViewModel {
    var todos: [Todo] = []
    var currentDate: Date = .now
    var editable: Bool = true
    var isLoading: Bool = false
    var error: String?
    var isOffline: Bool = false
    var newTaskTitle: String = ""

    private let api = APIClient.shared
    private let calendar = Calendar.current
    private let monitor = NetworkMonitor.shared
    private var lastSeenDate: Date = .now
    private var modelContext: ModelContext?

    var dateString: String {
        formatDate(currentDate)
    }

    var dateLabel: String {
        if calendar.isDateInToday(currentDate) {
            return "Today"
        } else if calendar.isDateInYesterday(currentDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: currentDate)
        }
    }

    var dateSubLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: currentDate)
    }

    var isToday: Bool {
        calendar.isDateInToday(currentDate)
    }

    var canAddTask: Bool {
        isToday && editable
    }

    var uncompletedTodos: [Todo] {
        todos.filter { !$0.completed }
    }

    var completedTodos: [Todo] {
        todos.filter { $0.completed }
    }

    func setContext(_ context: ModelContext) {
        modelContext = context
        SyncEngine.shared.setContext(context)
    }

    func loadTodos() async {
        isLoading = true
        let date = dateString

        // オンラインなら先にキューを掃き出してからサーバ取得（取得結果に同期済み内容が反映される）
        if monitor.isOnline {
            await SyncEngine.shared.sync()
        }

        if monitor.isOnline {
            do {
                let response = try await api.fetchTodos(date: date)
                todos = response.todos
                editable = response.editable
                isOffline = false
                error = nil
                saveToCache(date: date, response: response)
                reloadWidget()
                isLoading = false
                return
            } catch {
                // フォールスルーしてキャッシュを読む
                self.error = error.localizedDescription
            }
        }

        if let cached = loadFromCache(date: date) {
            todos = cached.todos
            // オフライン時の編集はサーバ整合のため今日のみ許可
            editable = monitor.isOnline ? cached.editable : (cached.editable && isToday)
            isOffline = !monitor.isOnline
            if !monitor.isOnline { error = nil }
        } else {
            todos = []
            // キャッシュ無しでも、今日に限ってはオフラインで書き込みを許可
            editable = isToday
            isOffline = !monitor.isOnline
            if !monitor.isOnline { error = nil }
        }
        isLoading = false
    }

    func addTodo() async {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTaskTitle = ""

        if monitor.isOnline {
            do {
                let todo = try await api.createTodo(title: title)
                todos.append(todo)
                upsertCache(todo)
                reloadWidget()
                return
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        // オフライン: 今日のみ追加可
        guard isToday else { return }
        let tempId = "tmp_\(UUID().uuidString)"
        let now = ISO8601DateFormatter().string(from: .now)
        let nextPosition = (todos.map { $0.position }.max() ?? -1) + 1
        let todo = Todo(
            id: tempId,
            title: title,
            date: dateString,
            completed: false,
            position: nextPosition,
            carriedOver: false,
            createdAt: now,
            updatedAt: now
        )
        todos.append(todo)
        upsertCache(todo)
        enqueue(.create, todoId: tempId, date: dateString, title: title)
        reloadWidget()
    }

    func toggleCompleted(_ todo: Todo) async {
        guard editable else { return }
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        let newValue = !todo.completed
        let original = todos[i]
        todos[i].completed = newValue

        if monitor.isOnline {
            do {
                let updated = try await api.updateTodo(id: todo.id, completed: newValue)
                if let j = todos.firstIndex(where: { $0.id == todo.id }) {
                    todos[j] = updated
                }
                upsertCache(updated)
                reloadWidget()
                return
            } catch {
                if let j = todos.firstIndex(where: { $0.id == todo.id }) {
                    todos[j] = original
                }
                self.error = error.localizedDescription
                return
            }
        }

        guard isToday else {
            todos[i] = original
            return
        }
        upsertCache(todos[i])
        enqueue(.update, todoId: todo.id, date: dateString, completed: newValue)
        reloadWidget()
    }

    func updateTitle(id: String, title: String) async {
        guard editable else { return }
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        let original = todos[i]
        todos[i].title = title

        if monitor.isOnline {
            do {
                let updated = try await api.updateTodo(id: id, title: title)
                if let j = todos.firstIndex(where: { $0.id == id }) {
                    todos[j] = updated
                }
                upsertCache(updated)
                reloadWidget()
                return
            } catch {
                if let j = todos.firstIndex(where: { $0.id == id }) {
                    todos[j] = original
                }
                self.error = error.localizedDescription
                return
            }
        }

        guard isToday else {
            todos[i] = original
            return
        }
        upsertCache(todos[i])
        enqueue(.update, todoId: id, date: dateString, title: title)
        reloadWidget()
    }

    func deleteTodo(_ todo: Todo) async {
        guard editable else { return }

        if monitor.isOnline {
            do {
                try await api.deleteTodo(id: todo.id)
                todos.removeAll { $0.id == todo.id }
                removeFromCache(id: todo.id)
                reloadWidget()
                return
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        guard isToday else { return }
        todos.removeAll { $0.id == todo.id }
        removeFromCache(id: todo.id)
        enqueue(.delete, todoId: todo.id, date: dateString)
        reloadWidget()
    }

    func moveTodo(fromId: String, toId: String) {
        var uncompleted = uncompletedTodos
        guard let fromIndex = uncompleted.firstIndex(where: { $0.id == fromId }),
              let toIndex = uncompleted.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }

        let item = uncompleted.remove(at: fromIndex)
        uncompleted.insert(item, at: toIndex)

        todos = uncompleted + completedTodos
    }

    func syncReorder() {
        let uncompleted = uncompletedTodos
        Task {
            let items = uncompleted.enumerated().map { (i, todo) in
                (id: todo.id, position: i)
            }

            if monitor.isOnline {
                do {
                    try await api.reorderTodos(items: items)
                    applyReorderToCache(items: items)
                    reloadWidget()
                    return
                } catch {
                    self.error = error.localizedDescription
                    return
                }
            }

            guard isToday else { return }
            applyReorderToCache(items: items)
            let payload = items.map { ReorderItemPayload(id: $0.id, position: $0.position) }
            let json = (try? JSONEncoder().encode(payload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            enqueue(.reorder, date: dateString, reorderItemsJSON: json)
            reloadWidget()
        }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    func resetToTodayIfDayChanged() {
        if !calendar.isDate(lastSeenDate, inSameDayAs: .now) {
            currentDate = .now
        }
        lastSeenDate = .now
    }

    func goToPreviousDay() {
        currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        Task { await loadTodos() }
    }

    func goToNextDay() {
        guard !isToday else { return }
        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        Task { await loadTodos() }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Cache

    private func saveToCache(date: String, response: TodosResponse) {
        guard let context = modelContext else { return }
        let todoDescriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.date == date }
        )
        let existing = (try? context.fetch(todoDescriptor)) ?? []
        let incomingIds = Set(response.todos.map { $0.id })
        for cached in existing where !incomingIds.contains(cached.id) {
            context.delete(cached)
        }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for todo in response.todos {
            if let cached = existingById[todo.id] {
                cached.apply(todo)
            } else {
                context.insert(CachedTodo(from: todo))
            }
        }
        let dateDescriptor = FetchDescriptor<CachedDate>(
            predicate: #Predicate { $0.date == date }
        )
        if let cachedDate = try? context.fetch(dateDescriptor).first {
            cachedDate.editable = response.editable
            cachedDate.lastFetchedAt = .now
        } else {
            context.insert(CachedDate(date: date, editable: response.editable, lastFetchedAt: .now))
        }
        try? context.save()
    }

    private func loadFromCache(date: String) -> (todos: [Todo], editable: Bool)? {
        guard let context = modelContext else { return nil }
        let dateDescriptor = FetchDescriptor<CachedDate>(
            predicate: #Predicate { $0.date == date }
        )
        guard let cachedDate = try? context.fetch(dateDescriptor).first else { return nil }
        let todoDescriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.date == date },
            sortBy: [SortDescriptor(\.position)]
        )
        let cached = (try? context.fetch(todoDescriptor)) ?? []
        return (cached.map { $0.toTodo() }, cachedDate.editable)
    }

    private func upsertCache(_ todo: Todo) {
        guard let context = modelContext else { return }
        let id = todo.id
        let descriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.apply(todo)
        } else {
            context.insert(CachedTodo(from: todo))
        }
        // この日付の CachedDate がまだ無ければ作成（オフライン初回作成のケース）
        let date = todo.date
        let dateDescriptor = FetchDescriptor<CachedDate>(
            predicate: #Predicate { $0.date == date }
        )
        if (try? context.fetch(dateDescriptor).first) == nil {
            context.insert(CachedDate(date: date, editable: true, lastFetchedAt: .now))
        }
        try? context.save()
    }

    private func removeFromCache(id: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            try? context.save()
        }
    }

    private func applyReorderToCache(items: [(id: String, position: Int)]) {
        guard let context = modelContext else { return }
        for (id, position) in items {
            let descriptor = FetchDescriptor<CachedTodo>(
                predicate: #Predicate { $0.id == id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.position = position
            }
        }
        try? context.save()
    }

    // MARK: - Pending operation queue

    private func enqueue(
        _ kind: PendingOperationKind,
        todoId: String? = nil,
        date: String,
        title: String? = nil,
        completed: Bool? = nil,
        reorderItemsJSON: String? = nil
    ) {
        guard let context = modelContext else { return }
        // reorder は同じ日付の既存 reorder を最新で上書き（キュー肥大化を抑制）
        if kind == .reorder {
            let kindString = PendingOperationKind.reorder.rawValue
            let descriptor = FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.kind == kindString && $0.date == date }
            )
            if let existing = try? context.fetch(descriptor) {
                for op in existing {
                    context.delete(op)
                }
            }
        }
        let op = PendingOperation(
            kind: kind,
            todoId: todoId,
            date: date,
            titlePayload: title,
            completedPayload: completed,
            reorderItemsJSON: reorderItemsJSON
        )
        context.insert(op)
        try? context.save()
        SyncEngine.shared.setContext(context)
    }
}
