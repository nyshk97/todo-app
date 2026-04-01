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
                            widgetCheckbox(todo.completed)

                            Text(todo.title)
                                .font(.system(size: 13))
                                .strikethrough(todo.completed)
                                .foregroundStyle(todo.completed ? Color(.systemGray) : Color(.darkGray))
                                .lineLimit(2)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(4)
    }

    private func widgetCheckbox(_ completed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(completed ? Color(red: 0.93, green: 0.78, blue: 0.30) : .white)
                .frame(width: 13, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(completed ? Color.clear : Color(.systemGray4), lineWidth: 1)
                .frame(width: 13, height: 13)
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(white: 0.3))
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(.darkGray))
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.systemGray))
            }
            Spacer()
            Text("\(entry.completedCount)/\(entry.totalCount)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(.systemGray))
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: entry.date)
    }
}
