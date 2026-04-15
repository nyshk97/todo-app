import SwiftUI

struct TaskDetailSheet: View {
    let viewModel: ShelfViewModel
    @State var task: Task
    let onDismiss: () -> Void

    @State private var editingTitle: String = ""
    @State private var isEditingTitle = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    @State private var showMoveToTodayConfirm = false
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleSection
                    dueDateSection
                    moveSection
                    commentsSection
                }
                .padding(16)
            }
            .background(Theme.bgPanel)
            .navigationTitle("タスク詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onDismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .toolbarBackground(Theme.bgPanel, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            comments = await viewModel.fetchComments(taskId: task.id)
        }
        .alert("タスクを削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) {
                Swift.Task {
                    await viewModel.deleteTask(task)
                    onDismiss()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("今日のTODOに移動しますか？", isPresented: $showMoveToTodayConfirm) {
            Button("移動") {
                Swift.Task {
                    await viewModel.moveTaskToToday(task)
                    onDismiss()
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("「\(task.title)」を今日のTODOに移動し、Shelfから削除します")
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveTaskSheet(viewModel: viewModel, task: task, onDismiss: {
                showMoveSheet = false
                onDismiss()
            })
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingTitle {
                TextField("タイトル", text: $editingTitle)
                    .font(.title3)
                    .foregroundStyle(Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let title = editingTitle.trimmingCharacters(in: .whitespaces)
                        if !title.isEmpty && title != task.title {
                            Swift.Task {
                                await viewModel.updateTask(task, title: title)
                                task.title = title
                            }
                        }
                        isEditingTitle = false
                    }
            } else {
                Text(task.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .onTapGesture {
                        editingTitle = task.title
                        isEditingTitle = true
                    }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Due Date

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("期日")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            HStack {
                if let dueDate = task.dueDate {
                    DueDateBadge(dateString: dueDate)
                    Button {
                        Swift.Task {
                            await viewModel.updateTask(task, dueDate: .some(nil))
                            task.dueDate = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textQuaternary)
                    }
                } else {
                    Text("未設定")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textQuaternary)
                }

                Spacer()

                Button {
                    if let d = task.dueDate, let parsed = DateHelper.parseDate(d) {
                        selectedDate = parsed
                    }
                    showDatePicker.toggle()
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if showDatePicker {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.orange)
                    .onChange(of: selectedDate) {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
                        let dateStr = formatter.string(from: selectedDate)
                        Swift.Task {
                            await viewModel.updateTask(task, dueDate: .some(dateStr))
                            task.dueDate = dateStr
                        }
                        showDatePicker = false
                    }
            }
        }
        .padding(12)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Move

    private var moveSection: some View {
        HStack(spacing: 12) {
            Button {
                showMoveSheet = true
            } label: {
                Label("移動", systemImage: "arrow.right.arrow.left")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                showMoveToTodayConfirm = true
            } label: {
                Label("今日のTODOへ", systemImage: "arrow.up.forward")
                    .font(.subheadline)
                    .foregroundStyle(Theme.green)
            }
        }
        .padding(12)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("コメント")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            ForEach(comments) { comment in
                CommentRow(
                    comment: comment,
                    onUpdate: { content in
                        if let updated = await viewModel.updateComment(comment, content: content) {
                            if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
                                comments[idx] = updated
                            }
                        }
                    },
                    onDelete: {
                        await viewModel.deleteComment(comment)
                        comments.removeAll { $0.id == comment.id }
                    }
                )
            }

            // Add comment
            HStack(spacing: 8) {
                TextField("コメントを追加", text: $newCommentText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit { submitComment() }

                if !newCommentText.isEmpty {
                    Button { submitComment() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(10)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func submitComment() {
        let content = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        newCommentText = ""
        Swift.Task {
            if let comment = await viewModel.createComment(taskId: task.id, content: content) {
                comments.append(comment)
            }
        }
    }
}

// MARK: - Comment Row

struct CommentRow: View {
    let comment: Comment
    let onUpdate: (String) async -> Void
    let onDelete: () async -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                TextField("コメント", text: $editText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit {
                        let content = editText.trimmingCharacters(in: .whitespaces)
                        if !content.isEmpty && content != comment.content {
                            Swift.Task { await onUpdate(content) }
                        }
                        isEditing = false
                    }
            } else {
                linkedText(comment.content)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(formatTimestamp(comment.createdAt))
                .font(.caption2)
                .foregroundStyle(Theme.textQuaternary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button {
                editText = comment.content
                isEditing = true
            } label: {
                Label("編集", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Swift.Task { await onDelete() }
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private func formatTimestamp(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return String(iso.prefix(10)) }
        return "\(month)/\(day)"
    }
}

// MARK: - Move Task Sheet

struct MoveTaskSheet: View {
    let viewModel: ShelfViewModel
    let task: Task
    let onDismiss: () -> Void

    @State private var selectedProjectId: String = ""
    @State private var selectedSectionId: String? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.projects) { project in
                    SwiftUI.Section(project.name) {
                        // Unsectioned option
                        Button {
                            moveTask(toProject: project.id, section: nil)
                        } label: {
                            HStack {
                                Text("(セクションなし)")
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                if task.projectId == project.id && task.sectionId == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.green)
                                }
                            }
                        }

                        ForEach(viewModel.sectionsFor(projectId: project.id)) { section in
                            Button {
                                moveTask(toProject: project.id, section: section.id)
                            } label: {
                                HStack {
                                    Text(section.name)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if task.projectId == project.id && task.sectionId == section.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bgPanel)
            .navigationTitle("移動先を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func moveTask(toProject: String, section: String?) {
        Swift.Task {
            await viewModel.moveTask(task, toProjectId: toProject, sectionId: section)
            onDismiss()
        }
    }
}
