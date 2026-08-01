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
                    isPending: viewModel.pendingTaskIds.contains(task.id),
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

