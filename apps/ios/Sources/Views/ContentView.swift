import SwiftUI

struct ContentView: View {
    @State private var viewModel = TodoViewModel()
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                headerView
                todoListView
            }
            .gesture(swipeGesture)

            if viewModel.canAddTask {
                addButton
            }
        }
        .task {
            await viewModel.loadTodos()
        }
        .alert("タスクを追加", isPresented: $viewModel.showingAddTask) {
            TextField("タスク名", text: $viewModel.newTaskTitle)
            Button("追加") {
                Task { await viewModel.addTodo() }
            }
            Button("キャンセル", role: .cancel) {
                viewModel.newTaskTitle = ""
            }
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
            if !viewModel.uncompletedTodos.isEmpty {
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
            } else if viewModel.todos.isEmpty {
                ContentUnavailableView("タスクなし", systemImage: "checkmark.circle")
            }
        }
    }

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

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            viewModel.showingAddTask = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.green, in: Circle())
                .shadow(radius: 4, y: 2)
        }
        .padding(24)
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }

                if horizontal < 0 {
                    // Left swipe → previous day
                    viewModel.goToPreviousDay()
                } else {
                    // Right swipe → next day (towards today)
                    viewModel.goToNextDay()
                }
            }
    }
}
