import Foundation
import SwiftUI

@MainActor
@Observable
final class TodoViewModel {
    var todos: [Todo] = []
    var currentDate: Date = .now
    var editable: Bool = true
    var isLoading: Bool = false
    var error: String?
    var newTaskTitle: String = ""

    private let api = APIClient.shared
    private let calendar = Calendar.current

    var dateString: String {
        formatDate(currentDate)
    }

    var dateLabel: String {
        if calendar.isDateInToday(currentDate) {
            return "Today"
        } else if calendar.isDateInYesterday(currentDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: currentDate)
        }
    }

    var dateSubLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: currentDate)
    }

    var isToday: Bool {
        calendar.isDateInToday(currentDate)
    }

    var canAddTask: Bool {
        isToday && editable
    }

    var uncompletedTodos: [Todo] {
        todos.filter { !$0.completed }
    }

    var completedTodos: [Todo] {
        todos.filter { $0.completed }
    }

    func loadTodos() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.fetchTodos(date: dateString)
            todos = response.todos
            editable = response.editable
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addTodo() async {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTaskTitle = ""
        do {
            let todo = try await api.createTodo(title: title)
            todos.append(todo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleCompleted(_ todo: Todo) async {
        guard editable else { return }
        do {
            let updated = try await api.updateTodo(id: todo.id, completed: !todo.completed)
            if let i = todos.firstIndex(where: { $0.id == todo.id }) {
                todos[i] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTitle(id: String, title: String) async {
        guard editable else { return }
        do {
            let updated = try await api.updateTodo(id: id, title: title)
            if let i = todos.firstIndex(where: { $0.id == id }) {
                todos[i] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteTodo(_ todo: Todo) async {
        guard editable else { return }
        do {
            try await api.deleteTodo(id: todo.id)
            todos.removeAll { $0.id == todo.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func moveTodo(fromId: String, toId: String) {
        var uncompleted = uncompletedTodos
        guard let fromIndex = uncompleted.firstIndex(where: { $0.id == fromId }),
              let toIndex = uncompleted.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }

        let item = uncompleted.remove(at: fromIndex)
        uncompleted.insert(item, at: toIndex)

        todos = uncompleted + completedTodos
    }

    func syncReorder() {
        let uncompleted = uncompletedTodos
        Task {
            let items = uncompleted.enumerated().map { (i, todo) in
                (id: todo.id, position: i)
            }
            do {
                try await api.reorderTodos(items: items)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func goToPreviousDay() {
        currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        Task { await loadTodos() }
    }

    func goToNextDay() {
        guard !isToday else { return }
        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        Task { await loadTodos() }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
