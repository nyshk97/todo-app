import SwiftUI
import WidgetKit

struct TodoWidgetView: View {
    let entry: TodoEntry
    private var colors: AppColors { Theme.current }

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
                        .foregroundStyle(colors.textSecondary)
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
                                .foregroundStyle(todo.completed ? colors.textSecondary : colors.textPrimary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, -4)
    }

    private func widgetCheckbox(_ completed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(completed ? colors.checkboxFill : colors.checkboxBackground)
                .frame(width: 13, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(completed ? Color.clear : colors.checkboxBorder, lineWidth: 1)
                .frame(width: 13, height: 13)
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(colors.checkmarkColor)
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Text("\(entry.completedCount)/\(entry.totalCount)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: entry.date)
    }
}
