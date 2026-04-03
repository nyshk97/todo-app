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
        .overlay {
            if durationPickerTodoId != nil {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { durationPickerTodoId = nil }

                VStack(spacing: 0) {
                    ForEach([5, 15, 30, 60], id: \.self) { minutes in
                        Button {
                            setDuration(minutes)
                        } label: {
                            Text(minutes == 5 ? "~\(minutes) min" : "\(minutes) min")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        if minutes != 60 {
                            Divider().overlay(colors.checkboxBorder)
                        }
                    }
                }
                .background(colors.listBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: colors.shadowColor, radius: 20, x: 0, y: 8)
                .padding(.horizontal, 60)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: durationPickerTodoId)
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

    private func durationBadgeColor(_ duration: Int?) -> Color {
        guard let d = duration else { return colors.checkboxBackground }
        if d <= 5 { return Color(red: 0.96, green: 0.91, blue: 0.76) }
        if d <= 15 { return Color(red: 0.93, green: 0.82, blue: 0.45) }
        if d <= 30 { return Color(red: 0.90, green: 0.68, blue: 0.30) }
        return Color(red: 0.85, green: 0.52, blue: 0.25)
    }

    private func durationBadge(_ todo: Todo) -> some View {
        let label = durationLabel(todo.duration)
        let hasValue = todo.duration != nil
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(durationBadgeColor(todo.duration))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(hasValue ? Color.clear : colors.checkboxBorder, lineWidth: 1.2)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(hasValue ? colors.checkmarkColor : colors.textSecondary)
        }
        .frame(width: 28, height: 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: todo.duration)
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
