import Foundation
import SwiftData
import WidgetKit

@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    var pendingCount: Int = 0
    var lastSyncError: String?

    private enum TempReplacementAction {
        case keepServerTodo
        case deleteServerTodo
    }

    private struct OperationSnapshot {
        let id: String
        let kind: PendingOperationKind
        let todoId: String?
        let date: String
        let titlePayload: String?
        let completedPayload: Bool?
        let reorderItemsJSON: String?

        init?(_ op: PendingOperation) {
            guard let kind = PendingOperationKind(rawValue: op.kind) else { return nil }
            self.id = op.id
            self.kind = kind
            self.todoId = op.todoId
            self.date = op.date
            self.titlePayload = op.titlePayload
            self.completedPayload = op.completedPayload
            self.reorderItemsJSON = op.reorderItemsJSON
        }
    }

    private let api = APIClient.shared
    private let monitor = NetworkMonitor.shared
    private var modelContext: ModelContext?
    private var isSyncing = false
    private let droppedOperationMessage = "Some pending changes could not sync"

    private init() {}

    func setContext(_ context: ModelContext) {
        modelContext = context
        refreshPendingCount()
    }

    @discardableResult
    func sync() async -> Bool {
        guard let context = modelContext else { return false }
        guard !isSyncing else { return false }
        guard monitor.isOnline else { return false }
        isSyncing = true
        defer {
            isSyncing = false
            refreshPendingCount()
        }

        var droppedOperation = false

        while let op = fetchNextOperation(in: context) {
            guard let snapshot = OperationSnapshot(op) else {
                context.delete(op)
                try? context.save()
                droppedOperation = true
                continue
            }
            do {
                try await execute(snapshot, in: context)
                deleteOperation(id: snapshot.id, in: context)
            } catch {
                if shouldDrop(error, for: snapshot) {
                    deleteOperation(id: snapshot.id, in: context)
                    droppedOperation = true
                    lastSyncError = droppedOperationMessage
                    continue
                }
                if let latest = fetchOperation(id: snapshot.id, in: context) {
                    latest.retryCount += 1
                    lastSyncError = error.localizedDescription
                    try? context.save()
                    return false
                }
                // 同期中にユーザー操作で取り消された op は、stale snapshot から再実行しない。
                continue
            }
        }
        lastSyncError = droppedOperation ? droppedOperationMessage : nil
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    private func execute(_ op: OperationSnapshot, in context: ModelContext) async throws {
        switch op.kind {
        case .create:
            guard let tempId = op.todoId, let title = op.titlePayload else { return }
            let serverTodo = try await api.createTodo(title: title, date: op.date)
            let action = try replaceTempId(
                tempId: tempId,
                with: serverTodo,
                currentOperationId: op.id,
                in: context
            )
            if case .deleteServerTodo = action {
                await deleteServerTodoCreatedForRemovedTemp(
                    id: serverTodo.id,
                    date: op.date,
                    in: context
                )
            }

        case .update:
            guard let id = op.todoId else { return }
            let updated = try await api.updateTodo(
                id: id,
                completed: op.completedPayload,
                title: op.titlePayload
            )
            updateCachedTodo(id: id, with: updated, in: context)

        case .delete:
            guard let id = op.todoId else { return }
            // tmp_ で始まる ID は create が未送信のまま削除されたケース
            // = サーバーには存在しないので API 呼ばずに済ませる
            if id.hasPrefix("tmp_") { return }
            do {
                try await api.deleteTodo(id: id)
            } catch APIError.httpError(let code) where code == 404 {
                // 既にサーバー側で消えていれば成功扱い
            }

        case .reorder:
            guard let json = op.reorderItemsJSON,
                  let data = json.data(using: .utf8),
                  let items = try? JSONDecoder().decode([ReorderItemPayload].self, from: data) else { return }
            guard !items.isEmpty else { return }
            let pairs = items.map { (id: $0.id, position: $0.position) }
            try await api.reorderTodos(items: pairs, date: op.date)
        }
    }

    private func replaceTempId(
        tempId: String,
        with serverTodo: Todo,
        currentOperationId: String,
        in context: ModelContext
    ) throws -> TempReplacementAction {
        let realId = serverTodo.id

        let deleteKind = PendingOperationKind.delete.rawValue
        let pendingDeleteDescriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.kind == deleteKind && $0.todoId == tempId }
        )
        let hasPendingDelete = ((try? context.fetchCount(pendingDeleteDescriptor)) ?? 0) > 0

        let cachedDescriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.id == tempId }
        )
        let hadCachedTemp: Bool
        if let cached = try context.fetch(cachedDescriptor).first {
            hadCachedTemp = true
            context.delete(cached)
        } else {
            hadCachedTemp = false
        }

        if hadCachedTemp && !hasPendingDelete {
            let realDescriptor = FetchDescriptor<CachedTodo>(
                predicate: #Predicate { $0.id == realId }
            )
            if let existing = try context.fetch(realDescriptor).first {
                existing.apply(serverTodo)
            } else {
                context.insert(CachedTodo(from: serverTodo))
            }
        }

        if hadCachedTemp || hasPendingDelete {
            try replacePendingTodoReferences(
                tempId: tempId,
                realId: realId,
                excluding: currentOperationId,
                in: context
            )
            try rewriteReorderPayloads(in: context) { item in
                item.id == tempId
                    ? ReorderItemPayload(id: realId, position: item.position)
                    : item
            }
            try context.save()
            return .keepServerTodo
        }

        try deletePendingTodoReferences(
            tempId: tempId,
            excluding: currentOperationId,
            in: context
        )
        try rewriteReorderPayloads(in: context) { item in
            item.id == tempId ? nil : item
        }
        try context.save()
        return .deleteServerTodo
    }

    private func replacePendingTodoReferences(
        tempId: String,
        realId: String,
        excluding operationId: String,
        in context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.todoId == tempId }
        )
        for op in try context.fetch(descriptor) where op.id != operationId {
            op.todoId = realId
        }
    }

    private func deletePendingTodoReferences(
        tempId: String,
        excluding operationId: String,
        in context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.todoId == tempId }
        )
        for op in try context.fetch(descriptor) where op.id != operationId {
            context.delete(op)
        }
    }

    private func rewriteReorderPayloads(
        in context: ModelContext,
        transform: (ReorderItemPayload) -> ReorderItemPayload?
    ) throws {
        let reorderKind = PendingOperationKind.reorder.rawValue
        let reorderDescriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.kind == reorderKind }
        )
        for op in try context.fetch(reorderDescriptor) {
            guard let json = op.reorderItemsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ReorderItemPayload].self, from: data) else { continue }
            let items = decoded
                .compactMap(transform)
                .sorted { $0.position < $1.position }
                .enumerated()
                .map { ReorderItemPayload(id: $0.element.id, position: $0.offset) }
            if items.isEmpty {
                context.delete(op)
            } else if let data = try? JSONEncoder().encode(items),
                      let json = String(data: data, encoding: .utf8) {
                op.reorderItemsJSON = json
            }
        }
    }

    private func deleteServerTodoCreatedForRemovedTemp(id: String, date: String, in context: ModelContext) async {
        do {
            try await api.deleteTodo(id: id)
        } catch APIError.httpError(let code) where code == 404 {
            // サーバー側で既に消えていれば完了扱い
        } catch {
            enqueueDeleteIfNeeded(id: id, date: date, in: context)
            lastSyncError = error.localizedDescription
        }
    }

    private func enqueueDeleteIfNeeded(id: String, date: String, in context: ModelContext) {
        let deleteKind = PendingOperationKind.delete.rawValue
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.kind == deleteKind && $0.todoId == id }
        )
        let exists = ((try? context.fetchCount(descriptor)) ?? 0) > 0
        if !exists {
            context.insert(PendingOperation(kind: .delete, todoId: id, date: date))
            try? context.save()
        }
    }

    private func shouldDrop(_ error: Error, for op: OperationSnapshot) -> Bool {
        guard case APIError.httpError(let code) = error else { return false }

        switch op.kind {
        case .create, .update, .delete:
            return [400, 403, 404, 409].contains(code)
        case .reorder:
            return [400, 403, 409].contains(code)
        }
    }

    private func fetchNextOperation(in context: ModelContext) -> PendingOperation? {
        let descriptor = FetchDescriptor<PendingOperation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try? context.fetch(descriptor).first
    }

    private func fetchOperation(id: String, in context: ModelContext) -> PendingOperation? {
        let operationId = id
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.id == operationId }
        )
        return try? context.fetch(descriptor).first
    }

    private func deleteOperation(id: String, in context: ModelContext) {
        guard let op = fetchOperation(id: id, in: context) else { return }
        context.delete(op)
        try? context.save()
    }

    private func updateCachedTodo(id: String, with todo: Todo, in context: ModelContext) {
        let descriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.apply(todo)
            try? context.save()
        }
    }

    private func refreshPendingCount() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<PendingOperation>()
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}
