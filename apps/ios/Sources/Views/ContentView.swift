import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = TodoViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var draggingTodoId: String?
    @State private var editingTodoId: String?
    @State private var editingTitle: String = ""
    @State private var swipeOffset: CGFloat = 0
    @State private var swipingTodoId: String?
    @State private var durationPickerTodoId: String?
    @Environment(\.scenePhase) private var scenePhase

    private var colors: AppColors { Theme.current }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            todoListView
        }
        .background(colors.panelBackground)
        .gesture(swipeGesture)
        .task {
            await viewModel.loadTodos()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await viewModel.loadTodos() }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(viewModel.dateLabel)
                    .font(.system(size: 34, weight: .bold))
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
                        .font(.title2)
                        .foregroundStyle(colors.textPrimary)
                }
                Spacer()
                if !viewModel.isToday {
                    Button {
                        viewModel.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundStyle(colors.textPrimary)
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
        .background(colors.listBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: colors.shadowColor, radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.todos.isEmpty && !viewModel.canAddTask {
                VStack(spacing: 12) {
                    Text("—")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(colors.textSecondary.opacity(0.5))
                    Text("No tasks")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
        .confirmationDialog("Duration", isPresented: Binding(
            get: { durationPickerTodoId != nil },
            set: { if !$0 { durationPickerTodoId = nil } }
        )) {
            Button("~5 min") { setDuration(5) }
            Button("15 min") { setDuration(15) }
            Button("30 min") { setDuration(30) }
            Button("60 min") { setDuration(60) }
            Button("Clear", role: .destructive) { setDuration(nil) }
            Button("Cancel", role: .cancel) { durationPickerTodoId = nil }
        }
    }

    private func setDuration(_ duration: Int?) {
        guard let todoId = durationPickerTodoId else { return }
        durationPickerTodoId = nil
        Task { await viewModel.updateDuration(id: todoId, duration: duration) }
    }

    // MARK: - Inline Add

    private var addTaskRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.textSecondary)

            TextField("Add a task", text: $viewModel.newTaskTitle, prompt: Text("Add a task").foregroundStyle(colors.textSecondary))
                .font(.system(size: 15))
                .foregroundStyle(colors.textPrimary)
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit {
                    let title = viewModel.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if title.isEmpty {
                        isInputFocused = false
                    } else {
                        Task {
                            await viewModel.addTodo()
                            isInputFocused = true
                        }
                    }
                }
        }
    }

    private func durationLabel(_ duration: Int?) -> String {
        guard let d = duration else { return "-" }
        if d <= 5 { return "5" }
        if d <= 15 { return "15" }
        if d <= 30 { return "30" }
        return "60"
    }

    private func durationBadge(_ todo: Todo) -> some View {
        let label = durationLabel(todo.duration)
        let hasValue = todo.duration != nil
        return Text(label)
            .font(.system(size: 10, weight: hasValue ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(hasValue ? colors.textPrimary : colors.textSecondary)
            .frame(width: 30, alignment: .center)
    }

    private func checkboxIcon() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colors.checkboxFill)
                .frame(width: 15, height: 15)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(colors.checkmarkColor)
        }
    }

    // MARK: - Todo Row

    private let swipeThreshold: CGFloat = 80

    private func todoRow(_ todo: Todo) -> some View {
        let canSwipeComplete = viewModel.editable && !todo.completed && editingTodoId != todo.id
        let offset = swipingTodoId == todo.id ? swipeOffset : 0

        return ZStack(alignment: .leading) {
            // スワイプ時の背景（チェックマーク）
            if offset > 0 && canSwipeComplete {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                    if offset > swipeThreshold {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.green.opacity(min(1, offset / swipeThreshold)))
            }

            // メインの行コンテンツ
            HStack(spacing: 12) {
                if todo.completed {
                    checkboxIcon()
                } else {
                    Button {
                        guard viewModel.editable else { return }
                        durationPickerTodoId = todo.id
                    } label: {
                        durationBadge(todo)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.editable)
                }

                if editingTodoId == todo.id {
                    TextField("", text: $editingTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.textPrimary)
                        .submitLabel(.done)
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
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textSecondary)
                    }
                } else if viewModel.editable && !todo.completed {
                    linkedText(todo.title)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingTodoId = todo.id
                            editingTitle = todo.title
                        }
                } else {
                    linkedText(todo.title)
                        .font(.system(size: 15))
                        .strikethrough(todo.completed)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .offset(x: offset)
            .background(colors.listBackground)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard canSwipeComplete else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // 縦方向の動きが大きければスクロールに任せる
                    guard abs(horizontal) > abs(vertical) else { return }
                    if horizontal > 0 {
                        swipingTodoId = todo.id
                        swipeOffset = horizontal
                    }
                }
                .onEnded { value in
                    guard canSwipeComplete else { return }
                    if swipeOffset > swipeThreshold {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await viewModel.toggleCompleted(todo) }
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        swipeOffset = 0
                        swipingTodoId = nil
                    }
                }
        )
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
