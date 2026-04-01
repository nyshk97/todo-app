import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = TodoViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var draggingTodoId: String?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            todoListView
        }
        .gesture(swipeGesture)
        .task {
            await viewModel.loadTodos()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 4) {
            Text(viewModel.dateLabel)
                .font(.system(size: 34, weight: .bold))
            Text(viewModel.dateSubLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - List

    private var todoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
                        .opacity(draggingTodoId == todo.id ? 0.5 : 1)
                }

                // インライン入力欄
                if viewModel.canAddTask {
                    addTaskRow
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                // 完了済みタスク
                ForEach(viewModel.completedTodos) { todo in
                    todoRow(todo)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.todos.isEmpty && !viewModel.canAddTask {
                ContentUnavailableView("タスクなし", systemImage: "checkmark.circle")
            }
        }
    }

    // MARK: - Inline Add

    private var addTaskRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.quaternary)

            TextField("Add a task", text: $viewModel.newTaskTitle)
                .focused($isInputFocused)
                .onSubmit {
                    Task {
                        await viewModel.addTodo()
                        isInputFocused = true
                    }
                }
        }
    }

    // MARK: - Todo Row

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: 12) {
            Button {
                guard viewModel.editable else { return }
                Task { await viewModel.toggleCompleted(todo) }
            } label: {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.completed ? .green : .primary)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .strikethrough(todo.completed)
                .foregroundStyle(todo.completed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .contextMenu {
            if viewModel.editable {
                Button(role: .destructive) {
                    Task { await viewModel.deleteTodo(todo) }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }

                if horizontal < 0 {
                    viewModel.goToPreviousDay()
                } else {
                    viewModel.goToNextDay()
                }
            }
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
