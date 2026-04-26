import Foundation
import SwiftData
import WidgetKit

@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    var pendingCount: Int = 0
    var lastSyncError: String?

    private let api = APIClient.shared
    private let monitor = NetworkMonitor.shared
    private var modelContext: ModelContext?
    private var isSyncing = false

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

        let descriptor = FetchDescriptor<PendingOperation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let ops = try? context.fetch(descriptor) else { return false }
        if ops.isEmpty { return true }

        for op in ops {
            do {
                try await execute(op, in: context)
                context.delete(op)
                try? context.save()
            } catch {
                op.retryCount += 1
                lastSyncError = error.localizedDescription
                try? context.save()
                return false
            }
        }
        lastSyncError = nil
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    private func execute(_ op: PendingOperation, in context: ModelContext) async throws {
        guard let kind = PendingOperationKind(rawValue: op.kind) else { return }
        switch kind {
        case .create:
            guard let tempId = op.todoId, let title = op.titlePayload else { return }
            let serverTodo = try await api.createTodo(title: title)
            try replaceTempId(tempId: tempId, with: serverTodo, in: context)

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
            try await api.deleteTodo(id: id)

        case .reorder:
            guard let json = op.reorderItemsJSON,
                  let data = json.data(using: .utf8),
                  let items = try? JSONDecoder().decode([ReorderItemPayload].self, from: data) else { return }
            let pairs = items.map { (id: $0.id, position: $0.position) }
            try await api.reorderTodos(items: pairs)
        }
    }

    private func replaceTempId(tempId: String, with serverTodo: Todo, in context: ModelContext) throws {
        let realId = serverTodo.id

        let cachedDescriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.id == tempId }
        )
        if let cached = try context.fetch(cachedDescriptor).first {
            context.delete(cached)
        }
        let realDescriptor = FetchDescriptor<CachedTodo>(
            predicate: #Predicate { $0.id == realId }
        )
        if let existing = try context.fetch(realDescriptor).first {
            existing.apply(serverTodo)
        } else {
            context.insert(CachedTodo(from: serverTodo))
        }

        let opsDescriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.todoId == tempId }
        )
        if let ops = try? context.fetch(opsDescriptor) {
            for op in ops {
                op.todoId = realId
            }
        }

        let reorderKind = PendingOperationKind.reorder.rawValue
        let reorderDescriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.kind == reorderKind }
        )
        if let reorderOps = try? context.fetch(reorderDescriptor) {
            for op in reorderOps {
                guard let json = op.reorderItemsJSON else { continue }
                op.reorderItemsJSON = json.replacingOccurrences(of: tempId, with: realId)
            }
        }

        try context.save()
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
