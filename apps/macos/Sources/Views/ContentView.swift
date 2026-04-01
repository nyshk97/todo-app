import SwiftUI

struct ContentView: View {
    @State private var viewModel = TodoViewModel()
    @State private var editingTodoId: String?
    @State private var editingTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerView
            todoListView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.95, blue: 0.91))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await viewModel.loadTodos()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(viewModel.dateLabel)
                    .font(.system(size: 28, weight: .bold))
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
                        .font(.title3)
                        .foregroundStyle(Color(.darkGray))
                }
                .buttonStyle(.plain)
                Spacer()
                if !viewModel.isToday {
                    Button {
                        viewModel.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundStyle(Color(.darkGray))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }

    // MARK: - List

    private var todoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Spacer().frame(height: 8)
                // 未完了タスク
                ForEach(viewModel.uncompletedTodos) { todo in
                    todoRow(todo)
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
        .background(Color(red: 1.0, green: 0.97, blue: 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.todos.isEmpty && !viewModel.canAddTask {
                VStack(spacing: 12) {
                    Text("—")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(Color(.systemGray))
                    Text("No tasks")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(.systemGray))
                }
            }
        }
    }

    // MARK: - Inline Add

    private var addTaskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(.systemGray))

            TextField("Add a task", text: $viewModel.newTaskTitle)
                .font(.system(size: 13))
                .foregroundStyle(Color(.darkGray))
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
                .fill(completed ? Color(red: 0.93, green: 0.78, blue: 0.30) : .white)
                .frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(completed ? Color.clear : Color.gray.opacity(0.25), lineWidth: 1)
                .frame(width: 14, height: 14)
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(white: 0.3))
            }
        }
    }

    // MARK: - Todo Row

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            Button {
                guard viewModel.editable else { return }
                Task { await viewModel.toggleCompleted(todo) }
            } label: {
                checkboxIcon(todo.completed)
            }
            .buttonStyle(.plain)

            if editingTodoId == todo.id {
                TextField("", text: $editingTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.darkGray))
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
                        .foregroundStyle(Color(.systemGray))
                }
                .buttonStyle(.plain)
            } else if viewModel.editable && !todo.completed {
                Text(todo.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.darkGray))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingTodoId = todo.id
                        editingTitle = todo.title
                    }
            } else {
                Text(todo.title)
                    .font(.system(size: 13))
                    .strikethrough(todo.completed)
                    .foregroundStyle(todo.completed ? Color(.systemGray) : Color(.darkGray))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
