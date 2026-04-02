import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = TodoViewModel()
    @State private var editingTodoId: String?
    @State private var editingTitle: String = ""
    @State private var draggingTodoId: String?

    private var colors: AppColors { Theme.current }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            todoListView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await viewModel.loadTodos()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            Task { await viewModel.loadTodos() }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(viewModel.dateLabel)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text(viewModel.dateSubLabel)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button {
                    viewModel.goToPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(colors.textPrimary)
                }
                .buttonStyle(.plain)
                Spacer()
                if !viewModel.isToday {
                    Button {
                        viewModel.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundStyle(colors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(WindowDragView())
    }

    // MARK: - List

    private var todoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Spacer().frame(height: 8)
                // 未完了タスク
                ForEach(viewModel.uncompletedTodos) { todo in
                    todoRow(todo)
                        .onDrag {
                            draggingTodoId = todo.id
                            return NSItemProvider(object: todo.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: TodoDropDelegate(
                            todoId: todo.id,
                            viewModel: viewModel,
                            draggingTodoId: $draggingTodoId
                        ))
                }

                // インライン入力欄
                if viewModel.canAddTask {
                    addTaskRow
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                // 完了済みタスク
                ForEach(viewModel.completedTodos) { todo in
                    todoRow(todo)
                        .id("done-\(todo.id)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(colors.listBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: colors.shadowColor, radius: 8, x: 0, y: 3)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.todos.isEmpty && !viewModel.canAddTask {
                VStack(spacing: 12) {
                    Text("—")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(colors.textSecondary)
                    Text("No tasks")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Inline Add

    private var addTaskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textSecondary)

            TextField("Add a task", text: $viewModel.newTaskTitle)
                .font(.system(size: 13))
                .foregroundStyle(colors.textPrimary)
                .textFieldStyle(.plain)
                .onSubmit {
                    let title = viewModel.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        Task {
                            await viewModel.addTodo()
                        }
                    }
                }
        }
    }

    private func checkboxIcon(_ completed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(completed ? colors.checkboxFill : colors.checkboxBackground)
                .frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(completed ? Color.clear : colors.checkboxBorder, lineWidth: 1)
                .frame(width: 14, height: 14)
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(colors.checkmarkColor)
            }
        }
    }

    // MARK: - Todo Row

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            Button {
                guard viewModel.editable else { return }
                editingTodoId = nil
                Task { await viewModel.toggleCompleted(todo) }
            } label: {
                checkboxIcon(todo.completed)
            }
            .buttonStyle(.plain)

            if editingTodoId == todo.id {
                TextField("", text: $editingTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textPrimary)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let title = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty && title != todo.title {
                            Task { await viewModel.updateTitle(id: todo.id, title: title) }
                        }
                        editingTodoId = nil
                    }
                Button {
                    Task { await viewModel.deleteTodo(todo) }
                    editingTodoId = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
                .buttonStyle(.plain)
            } else if viewModel.editable && !todo.completed {
                linkedText(todo.title)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingTodoId = todo.id
                        editingTitle = todo.title
                    }
            } else {
                linkedText(todo.title)
                    .font(.system(size: 13))
                    .strikethrough(todo.completed)
                    .foregroundStyle(todo.completed ? colors.textSecondary : colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Drop Delegate

struct TodoDropDelegate: DropDelegate {
    let todoId: String
    let viewModel: TodoViewModel
    @Binding var draggingTodoId: String?

    func performDrop(info: DropInfo) -> Bool {
        viewModel.syncReorder()
        draggingTodoId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingId = draggingTodoId, draggingId != todoId else { return }
        withAnimation(.default) {
            viewModel.moveTodo(fromId: draggingId, toId: todoId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}

// MARK: - Window Drag Handle

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
