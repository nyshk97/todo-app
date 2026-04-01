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
        .background(Color(red: 0.96, green: 0.95, blue: 0.91))
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
                    .foregroundStyle(Color(.darkGray))
                Text(viewModel.dateSubLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemGray))
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button {
                    viewModel.goToPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(Color(.darkGray))
                }
                Spacer()
                if !viewModel.isToday {
                    Button {
                        viewModel.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundStyle(Color(.darkGray))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
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
                        .opacity(draggingTodoId == todo.id ? 0.5 : 1)
                }

                // インライン入力欄
                if viewModel.canAddTask {
                    addTaskRow
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }

                // 完了済みタスク
                ForEach(viewModel.completedTodos) { todo in
                    todoRow(todo)
                        .id("done-\(todo.id)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(red: 1.0, green: 0.97, blue: 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.todos.isEmpty && !viewModel.canAddTask {
                VStack(spacing: 12) {
                    Text("—")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Color(.systemGray3))
                    Text("No tasks")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(.systemGray2))
                }
            }
        }
    }

    // MARK: - Inline Add

    private var addTaskRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(.systemGray2))

            TextField("Add a task", text: $viewModel.newTaskTitle, prompt: Text("Add a task").foregroundStyle(Color(.systemGray2)))
                .font(.system(size: 15))
                .foregroundStyle(Color(.darkGray))
                .focused($isInputFocused)
                .onSubmit {
                    Task {
                        await viewModel.addTodo()
                        isInputFocused = true
                    }
                }
        }
    }

    private func checkboxIcon(_ completed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(completed ? Color(red: 0.93, green: 0.78, blue: 0.30) : .white)
                .frame(width: 15, height: 15)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(completed ? Color.clear : Color.gray.opacity(0.25), lineWidth: 1.2)
                .frame(width: 15, height: 15)
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(white: 0.3))
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
                checkboxIcon(todo.completed)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 15))
                .strikethrough(todo.completed)
                .foregroundStyle(todo.completed ? Color(.systemGray) : Color(.darkGray))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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

                if horizontal > 0 {
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
