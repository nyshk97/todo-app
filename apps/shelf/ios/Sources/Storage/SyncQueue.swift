import Foundation

enum PendingOperation: Codable, Equatable {
    case create(localId: String, projectId: String, sectionId: String?, title: String)
    case delete(taskId: String)
    case updateTitle(taskId: String, title: String)

    var taskId: String {
        switch self {
        case .create(let id, _, _, _): return id
        case .delete(let id): return id
        case .updateTitle(let id, _): return id
        }
    }
}

actor SyncQueue {
    static let shared = SyncQueue()

    private let filename = "queue.json"
    private var operations: [PendingOperation] = []
    private var loaded = false

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(filename)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let ops = try? JSONDecoder().decode([PendingOperation].self, from: data) {
            operations = ops
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(operations) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func snapshot() -> [PendingOperation] {
        loadIfNeeded()
        return operations
    }

    func count() -> Int {
        loadIfNeeded()
        return operations.count
    }

    func pendingTaskIds() -> Set<String> {
        loadIfNeeded()
        return Set(operations.map(\.taskId))
    }

    func enqueueCreate(localId: String, projectId: String, sectionId: String?, title: String) {
        loadIfNeeded()
        operations.append(.create(localId: localId, projectId: projectId, sectionId: sectionId, title: title))
        persist()
    }

    /// 削除をキュー化する。当該 taskId への未送信 create がある場合は両者を相殺する。
    /// 戻り値: true なら create と相殺してサーバー送信不要、false ならサーバーで delete 必要。
    @discardableResult
    func enqueueDelete(taskId: String) -> Bool {
        loadIfNeeded()
        if let createIdx = operations.firstIndex(where: {
            if case .create(let id, _, _, _) = $0, id == taskId { return true }
            return false
        }) {
            operations.remove(at: createIdx)
            operations.removeAll {
                if case .updateTitle(let id, _) = $0, id == taskId { return true }
                return false
            }
            persist()
            return true
        }
        operations.removeAll {
            if case .updateTitle(let id, _) = $0, id == taskId { return true }
            return false
        }
        operations.append(.delete(taskId: taskId))
        persist()
        return false
    }

    /// タイトル更新をキュー化する。Last-Write-Wins。
    /// 当該 taskId への未送信 create があれば create のタイトルを上書き、別途キューには積まない。
    func enqueueUpdateTitle(taskId: String, title: String) {
        loadIfNeeded()
        if let idx = operations.firstIndex(where: {
            if case .create(let id, _, _, _) = $0, id == taskId { return true }
            return false
        }) {
            if case .create(let id, let pid, let sid, _) = operations[idx] {
                operations[idx] = .create(localId: id, projectId: pid, sectionId: sid, title: title)
                persist()
                return
            }
        }
        operations.removeAll {
            if case .updateTitle(let id, _) = $0, id == taskId { return true }
            return false
        }
        operations.append(.updateTitle(taskId: taskId, title: title))
        persist()
    }

    func remove(_ op: PendingOperation) {
        loadIfNeeded()
        if let idx = operations.firstIndex(of: op) {
            operations.remove(at: idx)
            persist()
        }
    }

    /// 同期完了した create で、temp-ID を本物 ID に解決する。
    /// 後続の delete / updateTitle で対象 ID を書き換える。
    func resolveLocalId(_ localId: String, to realId: String) {
        loadIfNeeded()
        var changed = false
        for i in operations.indices {
            switch operations[i] {
            case .delete(let id) where id == localId:
                operations[i] = .delete(taskId: realId)
                changed = true
            case .updateTitle(let id, let title) where id == localId:
                operations[i] = .updateTitle(taskId: realId, title: title)
                changed = true
            default:
                break
            }
        }
        if changed { persist() }
    }
}
