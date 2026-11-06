import SwiftUI

struct ShareView: View {
    let items: [NSExtensionItem]
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var url: URL?
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?
    // コメントの追加だけ失敗して押し直したとき、タスクを二重に作らないよう覚えておく
    @State private var createdTaskId: String?
    @FocusState private var focused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    if loading {
                        ProgressView()
                    } else {
                        TextField("タイトル", text: $title, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($focused)
                            .disabled(createdTaskId != nil)
                    }
                    if let url {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let errorMessage {
                    SwiftUI.Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Shelf に追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("追加", action: save)
                            .disabled(loading || trimmedTitle.isEmpty)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            let content = await SharedContent.load(from: items)
            title = content.title
            url = content.url
            loading = false
            focused = true
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        let title = trimmedTitle
        let url = url
        Swift.Task {
            do {
                let taskId: String
                if let createdTaskId {
                    taskId = createdTaskId
                } else {
                    let projects = try await APIClient.shared.fetchProjects()
                    guard let shelf = projects.first(where: { $0.name == "Shelf" }) else {
                        errorMessage = "Shelf プロジェクトが見つかりません"
                        saving = false
                        return
                    }
                    taskId = try await APIClient.shared.createTask(title: title, projectId: shelf.id).id
                    createdTaskId = taskId
                }
                // URL はコメントに入れる（タイトルを短く保てて、コメントの URL はリンクになる）
                if let url {
                    _ = try await APIClient.shared.createComment(taskId: taskId, content: url.absoluteString)
                }
                onDone()
            } catch {
                errorMessage = createdTaskId == nil
                    ? "追加できませんでした（\(error.localizedDescription)）"
                    : "タスクは追加しましたが、URL のコメントを付けられませんでした（\(error.localizedDescription)）。もう一度「追加」でコメントだけ送り直します"
                saving = false
            }
        }
    }
}
