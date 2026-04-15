import SwiftUI

struct ContentView: View {
    @State private var viewModel = ShelfViewModel()
    @State private var selectedProjectId: String?

    var body: some View {
        Group {
            if !viewModel.isLoading && !viewModel.projects.isEmpty && selectedProjectId != nil {
                TabView(selection: $selectedProjectId) {
                    ForEach(viewModel.projects) { project in
                        ProjectView(viewModel: viewModel, projectId: project.id)
                            .tabItem {
                                Label(project.name, systemImage: tabIcon(for: project.name))
                            }
                            .tag(Optional(project.id))
                            .badge(badgeCount(for: project.id))
                    }

                    ArchiveView(viewModel: viewModel)
                        .tabItem {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tag(Optional("__archive__"))
                }
                .tint(Theme.textPrimary)
            } else if !viewModel.isLoading && viewModel.projects.isEmpty {
                Text("プロジェクトがありません")
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bgPage)
        .alert("エラー", isPresented: showErrorBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadAll()
            if selectedProjectId == nil {
                // デフォルトで "Deck" タブを選択
                let deck = viewModel.projects.first(where: { $0.name == "Deck" })
                selectedProjectId = deck?.id ?? viewModel.projects.first?.id
            }
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func tabIcon(for name: String) -> String {
        switch name {
        case "Todo": "checklist"
        case "Deck": "square.stack"
        case "Vault": "lock.shield"
        default: "folder"
        }
    }

    private func badgeCount(for projectId: String) -> Int {
        let projectTasks = viewModel.tasks[projectId] ?? []
        let now = Date()
        let jst = TimeZone(identifier: "Asia/Tokyo")!

        return projectTasks.filter { task in
            guard let dueDateStr = task.dueDate,
                  let dueDate = DateHelper.parseDate(dueDateStr) else { return false }
            var cal = Calendar.current
            cal.timeZone = jst
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: dueDate)).day ?? 0
            return days <= 3
        }.count
    }
}
