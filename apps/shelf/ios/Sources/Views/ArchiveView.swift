import SwiftUI

struct ArchiveView: View {
    let viewModel: ShelfViewModel

    @State private var selectedTask: ArchivedTask?

    var body: some View {
        Group {
            if viewModel.archivedTasks.isEmpty {
                Text("アーカイブされたタスクはありません")
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Text("\(viewModel.archivedTasks.count) 件のアーカイブ")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textQuaternary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        ForEach(viewModel.archivedTasks) { task in
                            ArchivedTaskRow(
                                task: task,
                                onTap: { selectedTask = task },
                                onRestore: {
                                    Swift.Task {
                                        await viewModel.restoreTask(task)
                                    }
                                },
                                onDelete: {
                                    Swift.Task {
                                        await viewModel.deleteArchivedTask(task)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(Theme.bgPage)
        .refreshable {
            await viewModel.fetchArchivedTasks()
        }
        .task {
            await viewModel.fetchArchivedTasks()
        }
        .sheet(item: $selectedTask) { task in
            ArchivedTaskDetailSheet(viewModel: viewModel, task: task)
        }
    }
}

// MARK: - Archived Task Row

struct ArchivedTaskRow: View {
    let task: ArchivedTask
    let onTap: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(task.projectName)
                            .font(.caption2)
                            .foregroundStyle(Theme.textQuaternary)

                        if let archivedAt = task.archivedAt {
                            Text("移動: \(archivedAt.prefix(10))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textQuaternary)
                        }

                        if task.commentCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 9))
                                Text("\(task.commentCount)")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Theme.textQuaternary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .contextMenu {
            Button {
                onRestore()
            } label: {
                Label("Shelfに戻す", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("完全に削除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onRestore()
            } label: {
                Label("戻す", systemImage: "arrow.uturn.backward")
            }
            .tint(Theme.green)
        }
    }
}

// MARK: - Archived Task Detail Sheet

struct ArchivedTaskDetailSheet: View {
    let viewModel: ShelfViewModel
    let task: ArchivedTask

    @State private var comments: [Comment] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(task.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("元プロジェクト")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text(task.projectName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if let archivedAt = task.archivedAt {
                            HStack {
                                Text("移動日")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Text(String(archivedAt.prefix(10)))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if let dueDate = task.dueDate {
                            HStack {
                                Text("期日")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Text(dueDate)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Comments
                    if !comments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("コメント")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)

                            ForEach(comments) { comment in
                                VStack(alignment: .leading, spacing: 4) {
                                    if !comment.content.isEmpty {
                                        linkedText(comment.content)
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.textSecondary)
                                    }

                                    // Attachments
                                    ForEach(comment.attachments) { attachment in
                                        AttachmentView(attachment: attachment, viewModel: viewModel)
                                    }

                                    Text(formatTimestamp(comment.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textQuaternary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(12)
                        .background(Theme.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
            .background(Theme.bgPanel)
            .navigationTitle("アーカイブ詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .toolbarBackground(Theme.bgPanel, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            comments = await viewModel.fetchComments(taskId: task.id)
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
