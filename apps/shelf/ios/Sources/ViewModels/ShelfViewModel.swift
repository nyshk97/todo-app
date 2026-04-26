import Foundation

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let retry: (() async -> Void)?
}

@Observable
@MainActor
final class ShelfViewModel {
    var projects: [Project] = []
    var sections: [String: [Section]] = [:]  // projectId -> sections
    var tasks: [String: [Task]] = [:]        // projectId -> tasks
    var upcomingCount: Int = 0
    var isLoading = false
    var errorMessage: String?
    var toasts: [ToastItem] = []
    var pendingCount: Int = 0
    var pendingTaskIds: Set<String> = []

    private let api = APIClient.shared
    private let cache = LocalCache.shared
    private let queue = SyncQueue.shared
    private var didLoadCache = false
    private var didLoadQueueState = false
    private var isSyncing = false

    private static func isNetworkError(_ error: Error) -> Bool {
        // APIError はサーバーから HTTP 応答が返っている = ネットには繋がっている
        !(error is APIError)
    }

    private func refreshPendingState() async {
        let ids = await queue.pendingTaskIds()
        let count = await queue.count()
        pendingTaskIds = ids
        pendingCount = count
    }

    func showToast(_ message: String, retry: (() async -> Void)? = nil) {
        let item = ToastItem(message: message, retry: retry)
        toasts.append(item)
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Initial Load

    func loadAll() async {
        if !didLoadCache {
            didLoadCache = true
            if let snapshot = await cache.load() {
                self.projects = snapshot.projects.sorted { $0.position < $1.position }
                self.sections = snapshot.sections
                self.tasks = snapshot.tasks
            }
        }
        if !didLoadQueueState {
            didLoadQueueState = true
            await refreshPendingState()
        }

        // キューに溜まっているものを先に同期してからフェッチ。
        // こうしないと「未同期の追加」が直後のフェッチで消える。
        await sync()

        let hasCache = !projects.isEmpty
        if !hasCache { isLoading = true }
        errorMessage = nil
        do {
            let projects = try await api.fetchProjects()
            self.projects = projects.sorted { $0.position < $1.position }

            async let upcomingResult = api.fetchUpcomingTasks()

            for project in projects {
                async let secs = api.fetchSections(projectId: project.id)
                async let tsks = api.fetchTasks(projectId: project.id)
                let (fetchedSections, fetchedTasks) = try await (secs, tsks)
                self.sections[project.id] = fetchedSections.sorted { $0.position < $1.position }
                self.tasks[project.id] = fetchedTasks.sorted { $0.position < $1.position }
            }

            let upcoming = try await upcomingResult
            self.upcomingCount = upcoming.count

            await persistCache()
        } catch {
            if !hasCache { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func persistCache() async {
        let snapshot = CacheSnapshot(projects: projects, sections: sections, tasks: tasks)
        await cache.save(snapshot)
    }

    // MARK: - Sync

    /// キューに溜まっている操作を順次サーバーへ送信する。
    /// オンライン時のみ実行。多重実行は防ぐ。
    func sync() async {
        guard NetworkMonitor.shared.isOnline, !isSyncing else { return }
        let ops = await queue.snapshot()
        guard !ops.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        for op in ops {
            do {
                switch op {
                case .create(let localId, let projectId, let sectionId, let title):
                    let task = try await api.createTask(title: title, projectId: projectId, sectionId: sectionId)
                    // ローカルの temp-ID を本物 ID に差し替え
                    if let idx = tasks[projectId]?.firstIndex(where: { $0.id == localId }) {
                        tasks[projectId]?[idx] = task
                    }
                    // 後続キュー内の delete/updateTitle 対象 ID を解決
                    await queue.resolveLocalId(localId, to: task.id)
                case .delete(let taskId):
                    do {
                        try await api.deleteTask(id: taskId)
                    } catch APIError.httpError(let code) where code == 404 {
                        // 既に消えていれば成功扱い
                    }
                case .updateTitle(let taskId, let title):
                    let updated = try await api.updateTask(id: taskId, title: title)
                    // ローカル側にも反映（同期中に他の更新がなければ no-op）
                    if let projectId = findProjectId(for: taskId),
                       let idx = tasks[projectId]?.firstIndex(where: { $0.id == taskId }) {
                        tasks[projectId]?[idx] = updated
                    }
                }
                await queue.remove(op)
                await refreshPendingState()
            } catch {
                if Self.isNetworkError(error) {
                    // ネットが切れたら中断、次回トリガーで再開
                    break
                } else {
                    // サーバー側エラー: 該当 op をスキップ（無限リトライ防止）
                    await queue.remove(op)
                    await refreshPendingState()
                    showToast("同期に失敗した操作がありました")
                }
            }
        }

        await persistCache()
    }

    private func findProjectId(for taskId: String) -> String? {
        for (pid, list) in tasks {
            if list.contains(where: { $0.id == taskId }) { return pid }
        }
        return nil
    }

    // MARK: - Projects

    func createProject(name: String) async {
        do {
            let project = try await api.createProject(name: name)
            projects.append(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProject(_ project: Project, name: String) async {
        do {
            let updated = try await api.updateProject(id: project.id, name: name)
            if let idx = projects.firstIndex(where: { $0.id == project.id }) {
                projects[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            try await api.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            sections.removeValue(forKey: project.id)
            tasks.removeValue(forKey: project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sections

    func sectionsFor(projectId: String) -> [Section] {
        sections[projectId] ?? []
    }

    func createSection(projectId: String, name: String) async {
        do {
            let section = try await api.createSection(projectId: projectId, name: name)
            sections[projectId, default: []].append(section)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSection(_ section: Section, name: String) async {
        do {
            let updated = try await api.updateSection(id: section.id, name: name)
            if let idx = sections[section.projectId]?.firstIndex(where: { $0.id == section.id }) {
                sections[section.projectId]?[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSection(_ section: Section) async {
        do {
            try await api.deleteSection(id: section.id)
            sections[section.projectId]?.removeAll { $0.id == section.id }
            // Tasks in this section become unsectioned
            if let projectTasks = tasks[section.projectId] {
                tasks[section.projectId] = projectTasks.map { task in
                    if task.sectionId == section.id {
                        var t = task
                        t.sectionId = nil
                        return t
                    }
                    return task
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderSections(projectId: String, sectionIds: [String]) async {
        let items = sectionIds.enumerated().map { (idx, id) in (id: id, position: idx) }
        // Optimistic update
        if var secs = sections[projectId] {
            secs.sort { a, b in
                let ai = sectionIds.firstIndex(of: a.id) ?? 0
                let bi = sectionIds.firstIndex(of: b.id) ?? 0
                return ai < bi
            }
            for i in secs.indices { secs[i].position = i }
            sections[projectId] = secs
        }
        do {
            try await api.reorderSections(projectId: projectId, items: items)
        } catch {
            errorMessage = error.localizedDescription
            await loadAll()
        }
    }

    // MARK: - Tasks

    func tasksFor(projectId: String, sectionId: String?) -> [Task] {
        (tasks[projectId] ?? []).filter { $0.sectionId == sectionId }.sorted { $0.position < $1.position }
    }

    func createTask(title: String, projectId: String, sectionId: String? = nil) async {
        let tempId = "temp-\(UUID().uuidString)"
        let now = ISO8601DateFormatter().string(from: Date())
        let sectionTasks = (tasks[projectId] ?? []).filter { $0.sectionId == sectionId }
        let optimistic = Task(
            id: tempId, projectId: projectId, sectionId: sectionId,
            title: title, dueDate: nil, position: sectionTasks.count,
            commentCount: 0, archivedAt: nil, createdAt: now, updatedAt: now
        )
        tasks[projectId, default: []].append(optimistic)

        if !NetworkMonitor.shared.isOnline {
            await queue.enqueueCreate(localId: tempId, projectId: projectId, sectionId: sectionId, title: title)
            await refreshPendingState()
            await persistCache()
            return
        }

        do {
            let task = try await api.createTask(title: title, projectId: projectId, sectionId: sectionId)
            if let idx = tasks[projectId]?.firstIndex(where: { $0.id == tempId }) {
                tasks[projectId]?[idx] = task
            }
            await persistCache()
        } catch {
            if Self.isNetworkError(error) {
                await queue.enqueueCreate(localId: tempId, projectId: projectId, sectionId: sectionId, title: title)
                await refreshPendingState()
                await persistCache()
            } else {
                tasks[projectId]?.removeAll { $0.id == tempId }
                showToast("タスクの作成に失敗しました") { [weak self] in
                    await self?.createTask(title: title, projectId: projectId, sectionId: sectionId)
                }
            }
        }
    }

    func updateTask(_ task: Task, title: String? = nil, dueDate: String?? = nil, projectId: String? = nil, sectionId: String?? = nil) async {
        // Optimistic update
        var optimistic = task
        if let t = title { optimistic.title = t }
        if let d = dueDate { optimistic.dueDate = d }
        replaceTask(old: task, new: optimistic)

        let isTitleOnly = title != nil && dueDate == nil && projectId == nil && sectionId == nil

        if isTitleOnly, !NetworkMonitor.shared.isOnline, let newTitle = title {
            await queue.enqueueUpdateTitle(taskId: task.id, title: newTitle)
            await refreshPendingState()
            await persistCache()
            return
        }

        do {
            let updated = try await api.updateTask(
                id: task.id,
                title: title,
                projectId: projectId,
                sectionId: sectionId,
                dueDate: dueDate
            )
            replaceTask(old: optimistic, new: updated)
            await persistCache()
        } catch {
            if isTitleOnly, Self.isNetworkError(error), let newTitle = title {
                await queue.enqueueUpdateTitle(taskId: task.id, title: newTitle)
                await refreshPendingState()
                await persistCache()
            } else {
                replaceTask(old: optimistic, new: task)
                showToast("タスクの更新に失敗しました") { [weak self] in
                    await self?.updateTask(task, title: title, dueDate: dueDate, projectId: projectId, sectionId: sectionId)
                }
            }
        }
    }

    func deleteTask(_ task: Task) async {
        let snapshot = tasks[task.projectId] ?? []
        tasks[task.projectId]?.removeAll { $0.id == task.id }

        // temp-ID（未送信 create）なら create を取り消すだけ
        if task.id.hasPrefix("temp-") {
            _ = await queue.enqueueDelete(taskId: task.id)
            await refreshPendingState()
            await persistCache()
            return
        }

        if !NetworkMonitor.shared.isOnline {
            await queue.enqueueDelete(taskId: task.id)
            await refreshPendingState()
            await persistCache()
            return
        }

        do {
            try await api.deleteTask(id: task.id)
            await persistCache()
        } catch {
            if Self.isNetworkError(error) {
                await queue.enqueueDelete(taskId: task.id)
                await refreshPendingState()
                await persistCache()
            } else if case APIError.httpError(let code) = error, code == 404 {
                // 既にサーバー側で消えている → 成功扱い
                await persistCache()
            } else {
                tasks[task.projectId] = snapshot
                showToast("タスクの削除に失敗しました") { [weak self] in
                    await self?.deleteTask(task)
                }
            }
        }
    }

    func moveTask(_ task: Task, toProjectId: String, sectionId: String?) async {
        do {
            let updated = try await api.updateTask(
                id: task.id,
                projectId: toProjectId,
                sectionId: .some(sectionId)
            )
            tasks[task.projectId]?.removeAll { $0.id == task.id }
            tasks[toProjectId, default: []].append(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderTasks(projectId: String, sectionId: String?, taskIds: [String]) async {
        let items = taskIds.enumerated().map { (idx, id) in (id: id, position: idx) }
        // Optimistic update
        if var projectTasks = tasks[projectId] {
            for i in projectTasks.indices {
                if let newPos = taskIds.firstIndex(of: projectTasks[i].id) {
                    projectTasks[i].position = newPos
                }
            }
            tasks[projectId] = projectTasks
        }
        do {
            try await api.reorderTasks(items: items)
        } catch {
            errorMessage = error.localizedDescription
            await loadAll()
        }
    }

    func moveTaskToToday(_ task: Task) async {
        do {
            let sectionName = task.sectionId.flatMap { sid in
                sections[task.projectId]?.first { $0.id == sid }?.name
            }
            let title = sectionName.map { "[\($0)] \(task.title)" } ?? task.title
            try await api.moveTaskToToday(id: task.id, title: title)
            tasks[task.projectId]?.removeAll { $0.id == task.id }
            // Refresh archived tasks if they were loaded
            if !archivedTasks.isEmpty {
                await fetchArchivedTasks()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Archive

    var archivedTasks: [ArchivedTask] = []

    func fetchArchivedTasks() async {
        do {
            archivedTasks = try await api.fetchArchivedTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreTask(_ archivedTask: ArchivedTask) async {
        do {
            let task = try await api.restoreTask(id: archivedTask.id)
            archivedTasks.removeAll { $0.id == archivedTask.id }
            tasks[task.projectId, default: []].append(task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteArchivedTask(_ archivedTask: ArchivedTask) async {
        do {
            try await api.deleteTask(id: archivedTask.id)
            archivedTasks.removeAll { $0.id == archivedTask.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Comments

    func fetchComments(taskId: String) async -> [Comment] {
        do {
            return try await api.fetchComments(taskId: taskId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func createComment(taskId: String, content: String, files: [(data: Data, filename: String, mimeType: String)] = []) async -> Comment? {
        do {
            return try await api.createComment(taskId: taskId, content: content, files: files)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateComment(_ comment: Comment, content: String) async -> Comment? {
        do {
            return try await api.updateComment(id: comment.id, content: content)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteComment(_ comment: Comment) async {
        do {
            try await api.deleteComment(id: comment.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Attachments

    func deleteAttachment(id: String) async {
        do {
            try await api.deleteAttachment(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated func attachmentURL(id: String) -> URL {
        APIClient.shared.attachmentURL(id: id)
    }

    // MARK: - Cross-section move (drag & drop)

    func moveTaskToSection(
        taskId: String,
        projectId: String,
        toSectionId: String?,
        insertAt: Int
    ) async {
        guard var projectTasks = tasks[projectId],
              let taskIdx = projectTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let snapshot = projectTasks

        var task = projectTasks[taskIdx]
        projectTasks.remove(at: taskIdx)
        task.sectionId = toSectionId

        let targetSectionTasks = projectTasks.filter { $0.sectionId == toSectionId }
        let globalInsertIndex: Int
        if insertAt >= targetSectionTasks.count {
            if let lastInSection = targetSectionTasks.last,
               let lastIdx = projectTasks.firstIndex(where: { $0.id == lastInSection.id }) {
                globalInsertIndex = lastIdx + 1
            } else {
                globalInsertIndex = projectTasks.count
            }
        } else {
            let anchorTask = targetSectionTasks[insertAt]
            globalInsertIndex = projectTasks.firstIndex(where: { $0.id == anchorTask.id }) ?? projectTasks.count
        }
        projectTasks.insert(task, at: globalInsertIndex)

        var pos = 0
        for i in projectTasks.indices where projectTasks[i].sectionId == toSectionId {
            projectTasks[i].position = pos
            pos += 1
        }

        tasks[projectId] = projectTasks

        do {
            _ = try await api.updateTask(id: taskId, projectId: projectId, sectionId: .some(toSectionId))
            let orderedIds = projectTasks
                .filter { $0.sectionId == toSectionId }
                .map(\.id)
            let items = orderedIds.enumerated().map { (id: $1, position: $0) }
            try await api.reorderTasks(items: items)
        } catch {
            tasks[projectId] = snapshot
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    func updateCommentCount(taskId: String, projectId: String, delta: Int) {
        if let idx = tasks[projectId]?.firstIndex(where: { $0.id == taskId }) {
            tasks[projectId]?[idx].commentCount += delta
        }
    }

    private func replaceTask(old: Task, new: Task) {
        if old.projectId != new.projectId {
            tasks[old.projectId]?.removeAll { $0.id == old.id }
            tasks[new.projectId, default: []].append(new)
        } else if let idx = tasks[old.projectId]?.firstIndex(where: { $0.id == old.id }) {
            tasks[old.projectId]?[idx] = new
        }
    }
}
