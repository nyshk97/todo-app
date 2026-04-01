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
        .background(Color(.systemGroupedBackground))
        .gesture(swipeGesture)
        .task {
            await viewModel.loadTodos()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(viewModel.dateLabel)
                    .font(.system(size: 34, weight: .bold))
                Text(viewModel.dateSubLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack {
                if !viewModel.isToday {
                    Button {
                        viewModel.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
            }
            .padding(.leading, 16)
        }
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }

                // 完了済みタスク
                ForEach(viewModel.completedTodos) { todo in
                    todoRow(todo)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(red: 1.0, green: 0.97, blue: 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
            Image(systemName: "square")
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
                Image(systemName: todo.completed ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(todo.completed ? .orange : Color(.systemGray3))
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .strikethrough(todo.completed)
                .foregroundStyle(todo.completed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
