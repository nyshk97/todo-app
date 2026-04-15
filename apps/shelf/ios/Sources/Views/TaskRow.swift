import SwiftUI
import UniformTypeIdentifiers

struct TaskRow: View {
    let task: Task
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Comment badge
                if task.commentCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.right")
                            .font(.caption2)
                        Text("\(task.commentCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.textQuaternary)
                }

                // Due date badge
                if let dueDate = task.dueDate {
                    DueDateBadge(dateString: dueDate)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Due Date Badge

struct DueDateBadge: View {
    let dateString: String

    var body: some View {
        Text(formattedDate)
            .font(.caption)
            .foregroundStyle(badgeColor)
    }

    private var formattedDate: String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return dateString }
        return "\(year)/\(month)/\(day)"
    }

    private var badgeColor: Color {
        switch dueDateStatus {
        case .overdue: Theme.red
        case .soon: Theme.orange
        case .normal: Theme.textQuaternary
        }
    }

    private enum DueStatus {
        case overdue, soon, normal
    }

    private var dueDateStatus: DueStatus {
        guard let date = DateHelper.parseDate(dateString) else { return .normal }
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        var cal = Calendar.current
        cal.timeZone = jst
        let now = Date()
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if days < 0 { return .overdue }
        if days <= 3 { return .soon }
        return .normal
    }
}

// MARK: - Date Helper

enum DateHelper {
    static func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter.date(from: str)
    }
}
