import SwiftUI

struct ContentView: View {
    @State private var viewModel = TodoViewModel()
    @FocusState private var isInputFocused: Bool

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
        List {
            Section {
                ForEach(viewModel.uncompletedTodos) { todo in
                    todoRow(todo)
                }
                .onMove { source, destination in
                    viewModel.moveTodos(from: source, to: destination)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let todo = viewModel.uncompletedTodos[index]
                        Task { await viewModel.deleteTodo(todo) }
                    }
                }

                // インライン入力欄
                if viewModel.canAddTask {
                    addTaskRow
                }
            }

            if !viewModel.completedTodos.isEmpty {
                Section {
                    ForEach(viewModel.completedTodos) { todo in
                        todoRow(todo)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let todo = viewModel.completedTodos[index]
                            Task { await viewModel.deleteTodo(todo) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
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
                        // 追加後にフォーカスを維持して連続入力可能に
                        isInputFocused = true
                    }
                }
        }
    }

    // MARK: - Todo Row

    private func todoRow(_ todo: Todo) -> some View {
        Button {
            guard viewModel.editable else { return }
            Task { await viewModel.toggleCompleted(todo) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.completed ? .green : .primary)

                Text(todo.title)
                    .strikethrough(todo.completed)
                    .foregroundStyle(todo.completed ? .secondary : .primary)
            }
        }
        .disabled(!viewModel.editable)
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
