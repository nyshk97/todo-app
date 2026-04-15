import SwiftUI
import UniformTypeIdentifiers

struct SectionView: View {
    let viewModel: ShelfViewModel
    let section: Section
    let projectId: String
    let onSelectTask: (Task) -> Void

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
    }
}

// MARK: - Task List (shared between sectioned and unsectioned)

struct TaskListView: View {
    let viewModel: ShelfViewModel
    let tasks: [Task]
    let projectId: String
    let sectionId: String?
    let onSelect: (Task) -> Void

    @State private var newTaskTitle = ""
    @State private var isAdding = false
    @State private var draggingTaskId: String?
    @State private var confirmDeleteTask: Task?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    onTap: { onSelect(task) },
                    onDelete: { confirmDeleteTask = task }
                )
                .onDrag {
                    draggingTaskId = task.id
                    return NSItemProvider(object: task.id as NSString)
                }
                .onDrop(of: [UTType.text], delegate: TaskDropDelegate(
                    taskId: task.id,
                    viewModel: viewModel,
                    projectId: projectId,
                    sectionId: sectionId,
                    draggingTaskId: $draggingTaskId
                ))
            }

            // Add task
            if isAdding {
                HStack(spacing: 8) {
                    TextField("タスク名", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
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
        .alert("タスクを削除しますか？", isPresented: Binding(
            get: { confirmDeleteTask != nil },
            set: { if !$0 { confirmDeleteTask = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let task = confirmDeleteTask {
                    Swift.Task { await viewModel.deleteTask(task) }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            if let task = confirmDeleteTask {
                Text("「\(task.title)」を削除します")
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

// MARK: - Drop Delegate

struct TaskDropDelegate: DropDelegate {
    let taskId: String
    let viewModel: ShelfViewModel
    let projectId: String
    let sectionId: String?
    @Binding var draggingTaskId: String?

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingId = draggingTaskId else { return false }
        let tasks = viewModel.tasksFor(projectId: projectId, sectionId: sectionId)
        let taskIds = tasks.map(\.id)
        Swift.Task {
            await viewModel.reorderTasks(projectId: projectId, sectionId: sectionId, taskIds: taskIds)
        }
        draggingTaskId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingId = draggingTaskId, draggingId != taskId else { return }
        let tasks = viewModel.tasksFor(projectId: projectId, sectionId: sectionId)
        guard let fromIndex = tasks.firstIndex(where: { $0.id == draggingId }),
              let toIndex = tasks.firstIndex(where: { $0.id == taskId }) else { return }

        withAnimation(.default) {
            viewModel.moveTaskLocally(projectId: projectId, fromIndex: fromIndex, toIndex: toIndex, sectionId: sectionId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}
