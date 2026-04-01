import SwiftUI
import WidgetKit

struct TodoWidgetView: View {
    let entry: TodoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.bottom, 8)

            if let error = entry.errorMessage {
                Spacer()
                HStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            } else if entry.todos.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("タスクなし")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.todos) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(todo.completed ? .green : .primary)

                            Text(todo.title)
                                .font(.system(size: 14))
                                .strikethrough(todo.completed)
                                .foregroundStyle(todo.completed ? .secondary : .primary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(4)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 18, weight: .bold))
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.completedCount)/\(entry.totalCount)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: entry.date)
    }
}
