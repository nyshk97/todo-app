import SwiftUI

struct ProjectView: View {
    let viewModel: ShelfViewModel
    let projectId: String

    @State private var selectedTask: Task?
    @State private var showAddSection = false
    @State private var newSectionName = ""
    @State private var showReorderSections = false
    @State private var dragController = DragController()

    var body: some View {
        let sections = viewModel.sectionsFor(projectId: projectId)
        let unsectionedTasks = viewModel.tasksFor(projectId: projectId, sectionId: nil)

        ScrollView {
            LazyVStack(spacing: 0) {
                // Header
                let project = viewModel.projects.first(where: { $0.id == projectId })
                let totalTasks = (viewModel.tasks[projectId] ?? []).count

                VStack(alignment: .leading, spacing: 6) {
                    Text(project?.name ?? "")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(totalTasks) items")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // Unsectioned tasks
                if !unsectionedTasks.isEmpty {
                    TaskListView(
                        viewModel: viewModel,
                        tasks: unsectionedTasks,
                        projectId: projectId,
                        sectionId: nil,
                        onSelect: { selectedTask = $0 }
                    )
                }

                // Sections
                ForEach(sections) { section in
                    SectionView(
                        viewModel: viewModel,
                        section: section,
                        projectId: projectId,
                        onSelectTask: { selectedTask = $0 },
                        onReorderSections: { showReorderSections = true }
                    )
                }

                // Add section button
                if showAddSection {
                    HStack(spacing: 8) {
                        TextField("セクション名", text: $newSectionName)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                            .onSubmit { submitNewSection() }

                        Button { submitNewSection() } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Button {
                            showAddSection = false
                            newSectionName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textQuaternary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                } else {
                    Button {
                        showAddSection = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.caption)
                            Text("セクションを追加")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Theme.textQuaternary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.bottom, 80)
            .coordinateSpace(name: "project")
            .onPreferenceChange(SectionFramesPreferenceKey.self) { value in
                dragController.sectionFrames = value
            }
            .onPreferenceChange(TaskFramesPreferenceKey.self) { value in
                dragController.taskFrames = value
            }
            .overlay(alignment: .topLeading) {
                if dragController.isActive,
                   let taskId = dragController.draggingTaskId,
                   let task = viewModel.tasks[projectId]?.first(where: { $0.id == taskId }) {
                    DragGhostView(task: task)
                        .frame(width: dragController.ghostSize.width, height: dragController.ghostSize.height)
                        .offset(
                            x: dragController.dragLocation.x - dragController.touchOffset.width,
                            y: dragController.dragLocation.y - dragController.touchOffset.height
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .refreshable {
            await viewModel.loadAll()
        }
        .background(Theme.bgPage)
        .environment(dragController)
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(viewModel: viewModel, task: task, onDismiss: { selectedTask = nil })
        }
        .sheet(isPresented: $showReorderSections) {
            SectionReorderSheet(viewModel: viewModel, projectId: projectId)
        }
    }

    private func submitNewSection() {
        let name = newSectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newSectionName = ""
        showAddSection = false
        Swift.Task {
            await viewModel.createSection(projectId: projectId, name: name)
        }
    }
}
