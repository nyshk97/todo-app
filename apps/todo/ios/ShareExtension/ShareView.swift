import SwiftUI
import WidgetKit

struct ShareView: View {
    let items: [NSExtensionItem]
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var url: URL?
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?
    // 送信に失敗して押し直しても二重に登録されないよう、シートごとに冪等キーを固定する
    @State private var todoId = UUID().uuidString.lowercased()
    @FocusState private var focused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading {
                        ProgressView()
                    } else {
                        TextField("タイトル", text: $title, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($focused)
                    }
                    if let url {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Today に追加")
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
        // todo のタスクはタイトルしか持たないので、URL は末尾に付ける（アプリ側でリンクになる）
        let text = [trimmedTitle, url?.absoluteString].compactMap { $0 }.joined(separator: " ")
        Task {
            do {
                _ = try await APIClient.shared.createTodo(title: text, id: todoId)
                WidgetCenter.shared.reloadAllTimelines()
                onDone()
            } catch {
                errorMessage = "追加できませんでした（\(error.localizedDescription)）"
                saving = false
            }
        }
    }
}
