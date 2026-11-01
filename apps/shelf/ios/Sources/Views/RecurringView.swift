import SwiftUI

/// 繰り返しタスクの決まりごと。API の cron も同じプロジェクト名で引く
enum Recurrence {
    static let projectName = "Recurring"
    static let maxInterval = 999

    static let units: [(value: String, label: String)] = [
        ("day", "日ごと"),
        ("week", "週ごと"),
        ("month", "か月ごと"),
        ("year", "年ごと"),
    ]

    static func label(unit: String, interval: Int) -> String {
        if interval == 1 {
            switch unit {
            case "day": return "毎日"
            case "week": return "毎週"
            case "month": return "毎月"
            default: return "毎年"
            }
        }
        switch unit {
        case "day": return "\(interval)日ごと"
        case "week": return "\(interval)週間ごと"
        case "month": return "\(interval)か月ごと"
        default: return "\(interval)年ごと"
        }
    }
}

struct RecurringView: View {
    let viewModel: ShelfViewModel
    let projectId: String

    @State private var selectedTask: Task?
    @State private var newTaskTitle = ""
    @FocusState private var isAddFocused: Bool

    /// 期日が未設定のものを先頭に、あとは次の期日の順で、月ごとにまとめる
    private var groups: [(label: String, tasks: [Task])] {
        let sorted = (viewModel.tasks[projectId] ?? []).sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            default: return a.position < b.position
            }
        }
        var result: [(label: String, tasks: [Task])] = []
        for task in sorted {
            let label = Self.groupLabel(task.dueDate)
            if result.last?.label == label {
                result[result.count - 1].tasks.append(task)
            } else {
                result.append((label, [task]))
            }
        }
        return result
    }

    private static func groupLabel(_ dueDate: String?) -> String {
        guard let dueDate else { return "期日未設定" }
        let parts = dueDate.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]) else { return dueDate }
        return "\(y)年\(m)月"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("期日の朝5時に、Shelfの先頭へ複製されます（ここの期日は次の回へ進みます）")
                    .font(.caption)
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(Theme.textQuaternary)
                    TextField("タスクを追加", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .focused($isAddFocused)
                        .submitLabel(.done)
                        .onSubmit { submitNewTask() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                ForEach(groups, id: \.label) { group in
                    Text(group.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
                        }

                    ForEach(group.tasks) { task in
                        RecurringTaskRow(task: task)
                            .onTapGesture { selectedTask = task }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .background(Theme.bgPage)
        .refreshable {
            await viewModel.loadAll()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(viewModel: viewModel, task: task, onDismiss: { selectedTask = nil })
        }
    }

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newTaskTitle = ""
        Swift.Task {
            await viewModel.createTask(title: title, projectId: projectId)
        }
    }
}

struct RecurringTaskRow: View {
    let task: Task

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 10) {
                    if let dueDate = task.dueDate {
                        Text(Self.formatDate(dueDate))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let unit = task.repeatUnit, let interval = task.repeatInterval {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                            Text(Recurrence.label(unit: unit, interval: interval))
                        }
                        .foregroundStyle(Theme.textQuaternary)
                    } else {
                        Text("繰り返し未設定")
                            .foregroundStyle(Theme.orange)
                    }
                }
                .font(.caption)
            }

            Spacer()

            if task.commentCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.right")
                    Text("\(task.commentCount)")
                }
                .font(.caption2)
                .foregroundStyle(Theme.textQuaternary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
        }
    }

    private static func formatDate(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return dateString
        }
        return "\(y)/\(m)/\(d)"
    }
}
