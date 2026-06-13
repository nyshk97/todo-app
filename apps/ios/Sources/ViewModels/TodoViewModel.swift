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

    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed,
    ]

    private static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return retryableURLErrorCodes.contains(urlError.code)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return retryableURLErrorCodes.contains(URLError.Code(rawValue: nsError.code))
        }
        return false
    }

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
        let date = dateString
        let cached = loadFromCache(date: date)

        if let cached {
            applyCached(cached, online: monitor.isOnline)
            isLoading = false
        } else {
            isLoading = true
        }

        // オンラインなら先にキューを掃き出してからサーバ取得（取得結果に同期済み内容が反映される）
        if monitor.isOnline {
            await SyncEngine.shared.sync()
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
                if Self.isNetworkError(error) {
                    if cached == nil {
                        applyEmptyOfflineState()
                    } else {
                        isOffline = true
                        self.error = nil
                    }
                } else {
                    self.error = error.localizedDescription
                }
                isLoading = false
                return
            }
        }

        if let cached {
            applyCached(cached, online: false)
        } else if !monitor.isOnline {
            applyEmptyOfflineState()
        }
        isLoading = false
    }

    private func applyCached(_ cached: (todos: [Todo], editable: Bool), online: Bool) {
        todos = cached.todos
        editable = online ? cached.editable : (cached.editable && isToday)
        isOffline = !online
        if !online { error = nil }
    }

    private func applyEmptyOfflineState() {
        todos = []
        // キャッシュ無しでも、今日に限ってはオフラインで書き込みを許可
        editable = isToday
        isOffline = true
        error = nil
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
                if Self.isNetworkError(error), isToday {
                    addOfflineTodo(title: title)
                } else {
                    self.error = error.localizedDescription
                }
                return
            }
        }

        // オフライン: 今日のみ追加可
        guard isToday else { return }
        addOfflineTodo(title: title)
    }

    private func addOfflineTodo(title: String) {
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

        if todo.id.hasPrefix("tmp_") {
            upsertCache(todos[i])
            enqueue(.update, todoId: todo.id, date: dateString, completed: newValue)
            reloadWidget()
            return
        }

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
                if Self.isNetworkError(error), isToday,
                   let j = todos.firstIndex(where: { $0.id == todo.id }) {
                    upsertCache(todos[j])
                    enqueue(.update, todoId: todo.id, date: dateString, completed: newValue)
                    reloadWidget()
                    return
                } else {
                    if let j = todos.firstIndex(where: { $0.id == todo.id }) {
                        todos[j] = original
                    }
                    self.error = error.localizedDescription
                    return
                }
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

        if id.hasPrefix("tmp_") {
            upsertCache(todos[i])
            enqueue(.update, todoId: id, date: dateString, title: title)
            reloadWidget()
            return
        }

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
                if Self.isNetworkError(error), isToday,
                   let j = todos.firstIndex(where: { $0.id == id }) {
                    upsertCache(todos[j])
                    enqueue(.update, todoId: id, date: dateString, title: title)
                    reloadWidget()
                    return
                } else {
                    if let j = todos.firstIndex(where: { $0.id == id }) {
                        todos[j] = original
                    }
                    self.error = error.localizedDescription
                    return
                }
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

        if todo.id.hasPrefix("tmp_") {
            todos.removeAll { $0.id == todo.id }
            removeFromCache(id: todo.id)
            enqueue(.delete, todoId: todo.id, date: dateString)
            reloadWidget()
            return
        }

        if monitor.isOnline {
            do {
                try await api.deleteTodo(id: todo.id)
                todos.removeAll { $0.id == todo.id }
                removeFromCache(id: todo.id)
                reloadWidget()
                return
            } catch {
                if Self.isNetworkError(error), isToday {
                    todos.removeAll { $0.id == todo.id }
                    removeFromCache(id: todo.id)
                    enqueue(.delete, todoId: todo.id, date: dateString)
                    reloadWidget()
                } else {
                    self.error = error.localizedDescription
                }
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

            if monitor.isOnline && !items.contains(where: { $0.id.hasPrefix("tmp_") }) {
                do {
                    try await api.reorderTodos(items: items, date: dateString)
                    applyReorderToCache(items: items)
                    reloadWidget()
                    return
                } catch {
                    if !Self.isNetworkError(error) || !isToday {
                        self.error = error.localizedDescription
                        return
                    }
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
            if isEmptyReorderPayload(reorderItemsJSON) {
                try? context.save()
                SyncEngine.shared.setContext(context)
                return
            }
        }
        if kind == .delete, let todoId, todoId.hasPrefix("tmp_") {
            cancelPendingCreate(for: todoId, in: context)
            SyncEngine.shared.setContext(context)
            return
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

    private func cancelPendingCreate(for tempId: String, in context: ModelContext) {
        let createKind = PendingOperationKind.create.rawValue
        let updateKind = PendingOperationKind.update.rawValue
        let deleteDescriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate {
                ($0.kind == createKind || $0.kind == updateKind) && $0.todoId == tempId
            }
        )
        if let ops = try? context.fetch(deleteDescriptor) {
            for op in ops {
                context.delete(op)
            }
        }

        let reorderKind = PendingOperationKind.reorder.rawValue
        let reorderDescriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.kind == reorderKind }
        )
        if let reorderOps = try? context.fetch(reorderDescriptor) {
            for op in reorderOps {
                guard let json = op.reorderItemsJSON,
                      let data = json.data(using: .utf8),
                      var items = try? JSONDecoder().decode([ReorderItemPayload].self, from: data) else { continue }
                items = items
                    .filter { $0.id != tempId }
                    .sorted { $0.position < $1.position }
                    .enumerated()
                    .map { ReorderItemPayload(id: $0.element.id, position: $0.offset) }
                if items.isEmpty {
                    context.delete(op)
                } else {
                    op.reorderItemsJSON = (try? JSONEncoder().encode(items))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                }
            }
        }

        try? context.save()
    }

    private func isEmptyReorderPayload(_ json: String?) -> Bool {
        guard let json,
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReorderItemPayload].self, from: data) else {
            return false
        }
        return items.isEmpty
    }
}
