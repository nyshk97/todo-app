import SwiftUI
import WidgetKit

struct TodoEntry: TimelineEntry {
    let date: Date
    let todos: [WidgetTodo]
    let totalCount: Int
    let completedCount: Int
    let errorMessage: String?
}

struct WidgetTodo: Identifiable {
    let id: String
    let title: String
    let completed: Bool
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(
            date: .now,
            todos: [
                WidgetTodo(id: "1", title: "タスクを追加しよう", completed: false),
            ],
            totalCount: 1,
            completedCount: 0,
            errorMessage: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let entry = await fetchEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchEntry() async -> TodoEntry {
        do {
            let response = try await WidgetAPIClient.shared.fetchTodos()
            let todos = response.todos.prefix(12).map { todo in
                WidgetTodo(id: todo.id, title: todo.title, completed: todo.completed)
            }
            let completedCount = response.todos.filter { $0.completed }.count
            return TodoEntry(
                date: .now,
                todos: Array(todos),
                totalCount: response.todos.count,
                completedCount: completedCount,
                errorMessage: nil
            )
        } catch {
            return TodoEntry(
                date: .now,
                todos: [],
                totalCount: 0,
                completedCount: 0,
                errorMessage: error.localizedDescription
            )
        }
    }
}

struct TodoWidget: Widget {
    let kind = "TodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
                .containerBackground(Color(red: 1.0, green: 0.97, blue: 0.88), for: .widget)
        }
        .configurationDisplayName("Today's Tasks")
        .description("今日のタスク一覧を表示します")
        .supportedFamilies([.systemLarge])
    }
}
