import SwiftUI

struct DragGhostView: View {
    let task: Task

    var body: some View {
        TaskRow(task: task, onTap: {})
            .background(Theme.bgSurface)
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
            .scaleEffect(1.02)
            .opacity(0.95)
    }
}
