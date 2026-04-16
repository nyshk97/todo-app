import SwiftUI

enum AppDestination: Hashable {
    case vault(String)   // project id
    case archive
}

struct ContentView: View {
    @State private var viewModel = ShelfViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let mainProject = mainProject {
                    ProjectView(viewModel: viewModel, projectId: mainProject.id)
                        .overlay(alignment: .bottomTrailing) {
                            FabButton(
                                viewModel: viewModel,
                                vaultUpcomingCount: vaultUpcomingCount,
                                onNavigateVault: {
                                    if let vault = vaultProject {
                                        path.append(AppDestination.vault(vault.id))
                                    }
                                },
                                onNavigateArchive: {
                                    path.append(AppDestination.archive)
                                }
                            )
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                } else if !viewModel.isLoading {
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
            .navigationDestination(for: AppDestination.self) { dest in
                switch dest {
                case .vault(let projectId):
                    ProjectView(viewModel: viewModel, projectId: projectId)
                        .navigationTitle("Vault")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Theme.bgPanel, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                case .archive:
                    ArchiveView(viewModel: viewModel)
                        .navigationTitle("Archive")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Theme.bgPanel, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
            }
        }
        .tint(Theme.textPrimary)
        .overlay { ToastOverlay(viewModel: viewModel) }
        .alert("エラー", isPresented: showErrorBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadAll()
        }
    }

    private var mainProject: Project? {
        viewModel.projects.first(where: { $0.name == "Shelf" })
            ?? viewModel.projects.first(where: { $0.name == "Deck" })
            ?? viewModel.projects.first
    }

    private var vaultProject: Project? {
        viewModel.projects.first(where: { $0.name == "Vault" })
    }

    private var vaultUpcomingCount: Int {
        guard let vault = vaultProject else { return 0 }
        let vaultTasks = viewModel.tasks[vault.id] ?? []
        let now = Date()
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        return vaultTasks.filter { task in
            guard let dueDateStr = task.dueDate,
                  let dueDate = DateHelper.parseDate(dueDateStr) else { return false }
            var cal = Calendar.current
            cal.timeZone = jst
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: dueDate)).day ?? 0
            return days <= 3
        }.count
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

// MARK: - FAB

struct FabButton: View {
    let viewModel: ShelfViewModel
    let vaultUpcomingCount: Int
    let onNavigateVault: () -> Void
    let onNavigateArchive: () -> Void

    @State private var showMenu = false

    var body: some View {
        Menu {
            if viewModel.projects.contains(where: { $0.name == "Vault" }) {
                Button {
                    onNavigateVault()
                } label: {
                    Label("Vault", systemImage: "lock.shield")
                }
            }

            Button {
                onNavigateArchive()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Theme.bgElevated)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    .overlay {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }

                if vaultUpcomingCount > 0 {
                    Text("\(vaultUpcomingCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.orange)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
    }
}
