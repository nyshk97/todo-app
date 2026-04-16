import SwiftUI
import PhotosUI

struct TaskDetailSheet: View {
    let viewModel: ShelfViewModel
    @State var task: Task
    let onDismiss: () -> Void

    @State private var editingTitle: String = ""
    @FocusState private var isTitleFocused: Bool
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    @State private var showMoveToTodayConfirm = false
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingFiles: [(data: Data, filename: String, mimeType: String)] = []
    @State private var showFilePicker = false

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
            Text("「\(task.title)」を今日のTODOに移動します")
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveTaskSheet(viewModel: viewModel, task: task, onDismiss: {
                showMoveSheet = false
                onDismiss()
            })
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard pendingFiles.count < 5 else { break }
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        let mimeType = mimeTypeFor(url: url)
                        pendingFiles.append((data: data, filename: url.lastPathComponent, mimeType: mimeType))
                    }
                }
            }
        }
        .onChange(of: selectedPhotos) {
            Swift.Task {
                for item in selectedPhotos {
                    guard pendingFiles.count < 5 else { break }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                        let ext = mimeType.split(separator: "/").last.map(String.init) ?? "jpg"
                        pendingFiles.append((data: data, filename: "photo.\(ext)", mimeType: mimeType))
                    }
                }
                selectedPhotos = []
            }
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("タイトル", text: $editingTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitleIfChanged() }
                .onChange(of: isTitleFocused) {
                    if !isTitleFocused { saveTitleIfChanged() }
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { editingTitle = task.title }
    }

    private func saveTitleIfChanged() {
        let title = editingTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty && title != task.title {
            let newTitle = title
            Swift.Task {
                await viewModel.updateTask(task, title: newTitle)
                task.title = newTitle
            }
        }
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
                    viewModel: viewModel,
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
                        task.commentCount -= 1
                        viewModel.updateCommentCount(taskId: task.id, projectId: task.projectId, delta: -1)
                    },
                    onDeleteAttachment: { attachmentId in
                        await viewModel.deleteAttachment(id: attachmentId)
                        if let cIdx = comments.firstIndex(where: { $0.id == comment.id }) {
                            comments[cIdx].attachments.removeAll { $0.id == attachmentId }
                        }
                    }
                )
            }

            // Pending files preview
            if !pendingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(pendingFiles.enumerated()), id: \.offset) { index, file in
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(Theme.textQuaternary)
                            Text(file.filename)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                pendingFiles.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textQuaternary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Theme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Add comment
            HStack(spacing: 8) {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(0, 5 - pendingFiles.count), matching: .images) {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.textTertiary)
                        .font(.subheadline)
                }

                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .foregroundStyle(Theme.textTertiary)
                        .font(.subheadline)
                }

                ZStack(alignment: .leading) {
                    if newCommentText.isEmpty {
                        Text("コメントを追加")
                            .foregroundStyle(Theme.textQuaternary)
                            .font(.subheadline)
                    }
                    TextEditor(text: $newCommentText)
                        .foregroundStyle(Theme.textPrimary)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 20, maxHeight: 100)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !newCommentText.isEmpty || !pendingFiles.isEmpty {
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
        guard !content.isEmpty || !pendingFiles.isEmpty else { return }
        let filesToSend = pendingFiles
        newCommentText = ""
        pendingFiles = []
        Swift.Task {
            if let comment = await viewModel.createComment(taskId: task.id, content: content, files: filesToSend) {
                comments.append(comment)
                task.commentCount += 1
                viewModel.updateCommentCount(taskId: task.id, projectId: task.projectId, delta: 1)
            }
        }
    }

    private func mimeTypeFor(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Comment Row

struct CommentRow: View {
    let comment: Comment
    let viewModel: ShelfViewModel
    let onUpdate: (String) async -> Void
    let onDelete: () async -> Void
    let onDeleteAttachment: (String) async -> Void

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
                if !comment.content.isEmpty {
                    linkedText(comment.content)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Attachments
            ForEach(comment.attachments) { attachment in
                AttachmentView(attachment: attachment, viewModel: viewModel) {
                    Swift.Task { await onDeleteAttachment(attachment.id) }
                }
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
