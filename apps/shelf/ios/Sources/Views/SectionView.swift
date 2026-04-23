import SwiftUI

struct SectionView: View {
    let viewModel: ShelfViewModel
    let section: Section
    let projectId: String
    let onSelectTask: (Task) -> Void
    var onReorderSections: (() -> Void)?

    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    @State private var renameName = ""

    var body: some View {
        let tasks = viewModel.tasksFor(projectId: projectId, sectionId: section.id)

        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text(section.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bgPanel)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderStandard)
                    .frame(height: 1)
            }
            .contextMenu {
                Button {
                    renameName = section.name
                    showRenameAlert = true
                } label: {
                    Label("名前を変更", systemImage: "pencil")
                }
                Button {
                    onReorderSections?()
                } label: {
                    Label("セクションを並び替え", systemImage: "arrow.up.arrow.down")
                }
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
            .alert("セクション名を変更", isPresented: $showRenameAlert) {
                TextField("セクション名", text: $renameName)
                Button("変更") {
                    let name = renameName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Swift.Task { await viewModel.updateSection(section, name: name) }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .alert("セクションを削除しますか？", isPresented: $showDeleteAlert) {
                Button("削除", role: .destructive) {
                    Swift.Task { await viewModel.deleteSection(section) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("「\(section.name)」を削除します。タスクはセクション未所属になります。")
            }

            // Tasks
            TaskListView(
                viewModel: viewModel,
                tasks: tasks,
                projectId: projectId,
                sectionId: section.id,
                onSelect: onSelectTask
            )
        }
        .padding(.top, 8)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SectionFramesPreferenceKey.self,
                    value: [SectionFrameKey(sectionId: section.id): geo.frame(in: .named("project"))]
                )
            }
        )
    }
}

// MARK: - Task List (shared between sectioned and unsectioned)

struct TaskListView: View {
    let viewModel: ShelfViewModel
    let tasks: [Task]
    let projectId: String
    let sectionId: String?
    let onSelect: (Task) -> Void

    @Environment(DragController.self) private var dragController

    @State private var newTaskTitle = ""
    @State private var isAdding = false
    @FocusState private var isTextFieldFocused: Bool

    private var isDropTarget: Bool {
        dragController.isActive && dragController.currentDropTarget?.sectionId == sectionId
    }

    private func showsInsertionIndicator(at index: Int) -> Bool {
        guard isDropTarget,
              let target = dragController.currentDropTarget else { return false }
        return target.insertionIndex == index
    }

    var body: some View {
        VStack(spacing: 0) {
            if tasks.isEmpty && isDropTarget {
                Rectangle()
                    .fill(Theme.accentBright)
                    .frame(height: 2)
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRow(
                    task: task,
                    onTap: { onSelect(task) }
                )
                .opacity(dragController.draggingTaskId == task.id ? 0.3 : 1.0)
                .overlay(alignment: .top) {
                    if showsInsertionIndicator(at: index) {
                        Rectangle()
                            .fill(Theme.accentBright)
                            .frame(height: 2)
                    }
                }
                .overlay(alignment: .bottom) {
                    if index == tasks.count - 1 && showsInsertionIndicator(at: tasks.count) {
                        Rectangle()
                            .fill(Theme.accentBright)
                            .frame(height: 2)
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TaskFramesPreferenceKey.self,
                            value: [task.id: TaskFrameInfo(
                                sectionId: sectionId,
                                frame: geo.frame(in: .named("project"))
                            )]
                        )
                    }
                )
                .simultaneousGesture(dragGesture(for: task))
            }

            // Add task
            if isAdding {
                HStack(spacing: 8) {
                    TextField("タスク名", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .onSubmit {
                            submitNewTask()
                        }

                    if !newTaskTitle.isEmpty {
                        Button {
                            submitNewTask()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.trailing, 12)
                    }
                }
                .background(Theme.bgSurface)
            } else {
                Button {
                    isAdding = true
                    isTextFieldFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("タスクを追加")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(isDropTarget ? Theme.accentBright.opacity(0.08) : Color.clear)
        .background(unsectionedFrameReporter)
    }

    @ViewBuilder
    private var unsectionedFrameReporter: some View {
        if sectionId == nil {
            GeometryReader { geo in
                Color.clear.preference(
                    key: SectionFramesPreferenceKey.self,
                    value: [SectionFrameKey(sectionId: nil): geo.frame(in: .named("project"))]
                )
            }
        } else {
            Color.clear
        }
    }

    private func dragGesture(for task: Task) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("project")))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let dragValue):
                    guard let dragValue else { return }
                    if !dragController.isActive {
                        guard let frame = dragController.taskFrames[task.id]?.frame else { return }
                        let touchOffset = CGSize(
                            width: dragValue.startLocation.x - frame.minX,
                            height: dragValue.startLocation.y - frame.minY
                        )
                        dragController.startDrag(
                            taskId: task.id,
                            projectId: projectId,
                            sourceSectionId: sectionId,
                            touchOffset: touchOffset,
                            ghostSize: frame.size,
                            initialLocation: dragValue.location
                        )
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        dragController.updateLocation(dragValue.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let result = dragController.endDrag()
                guard let result else { return }
                applyDrop(result: result)
            }
    }

    private func applyDrop(result: DragController.DropResult) {
        let target = result.target

        if target.sectionId == result.sourceSectionId {
            // Same section — reorder
            let sectionTasks = viewModel.tasksFor(projectId: projectId, sectionId: target.sectionId)
            var taskIds = sectionTasks.map(\.id)
            guard let currentIndex = taskIds.firstIndex(of: result.taskId) else { return }

            taskIds.remove(at: currentIndex)
            var insertionIndex = target.insertionIndex
            if currentIndex < insertionIndex {
                insertionIndex -= 1
            }
            insertionIndex = max(0, min(insertionIndex, taskIds.count))
            taskIds.insert(result.taskId, at: insertionIndex)

            let originalIds = sectionTasks.map(\.id)
            guard taskIds != originalIds else { return }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Swift.Task {
                await viewModel.reorderTasks(projectId: projectId, sectionId: target.sectionId, taskIds: taskIds)
            }
        } else {
            // Cross-section move
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Swift.Task {
                await viewModel.moveTaskToSection(
                    taskId: result.taskId,
                    projectId: projectId,
                    toSectionId: target.sectionId,
                    insertAt: target.insertionIndex
                )
            }
        }
    }

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newTaskTitle = ""
        isAdding = false
        Swift.Task {
            await viewModel.createTask(title: title, projectId: projectId, sectionId: sectionId)
        }
    }
}

