import SwiftUI

struct DropTarget: Equatable {
    let sectionId: String?
    let insertionIndex: Int
}

struct TaskFrameInfo: Equatable {
    let sectionId: String?
    let frame: CGRect
}

@Observable
@MainActor
final class DragController {
    var draggingTaskId: String?
    var draggingTaskSourceSectionId: String?
    var draggingTaskProjectId: String?
    var dragLocation: CGPoint = .zero
    var touchOffset: CGSize = .zero
    var ghostSize: CGSize = .zero
    var currentDropTarget: DropTarget?

    var sectionFrames: [SectionFrameKey: CGRect] = [:]
    var taskFrames: [String: TaskFrameInfo] = [:]

    var sectionOrder: [String?] = []

    var isActive: Bool { draggingTaskId != nil }

    func startDrag(
        taskId: String,
        projectId: String,
        sourceSectionId: String?,
        touchOffset: CGSize,
        ghostSize: CGSize,
        initialLocation: CGPoint
    ) {
        self.draggingTaskId = taskId
        self.draggingTaskSourceSectionId = sourceSectionId
        self.draggingTaskProjectId = projectId
        self.touchOffset = touchOffset
        self.ghostSize = ghostSize
        self.dragLocation = initialLocation
        recomputeDropTarget()
    }

    func updateLocation(_ location: CGPoint) {
        dragLocation = location
        recomputeDropTarget()
    }

    struct DropResult {
        let taskId: String
        let sourceSectionId: String?
        let target: DropTarget
    }

    func endDrag() -> DropResult? {
        defer { reset() }
        guard let taskId = draggingTaskId, let target = currentDropTarget else {
            return nil
        }
        return DropResult(
            taskId: taskId,
            sourceSectionId: draggingTaskSourceSectionId,
            target: target
        )
    }

    func cancelDrag() {
        reset()
    }

    private func reset() {
        draggingTaskId = nil
        draggingTaskSourceSectionId = nil
        draggingTaskProjectId = nil
        dragLocation = .zero
        touchOffset = .zero
        ghostSize = .zero
        currentDropTarget = nil
    }

    private func recomputeDropTarget() {
        let point = dragLocation

        // Find which section the finger is over
        var hitSectionId: String? = nil
        var matched = false
        for (key, frame) in sectionFrames {
            if frame.contains(point) {
                hitSectionId = key.sectionId
                matched = true
                break
            }
        }
        if !matched {
            currentDropTarget = nil
            return
        }

        // Compute insertion index within the section by checking task frames
        let rowsInSection = taskFrames
            .filter { $0.value.sectionId == hitSectionId }
            .sorted { $0.value.frame.minY < $1.value.frame.minY }

        if rowsInSection.isEmpty {
            currentDropTarget = DropTarget(sectionId: hitSectionId, insertionIndex: 0)
            return
        }

        var insertionIndex = rowsInSection.count
        for (i, entry) in rowsInSection.enumerated() {
            let frame = entry.value.frame
            let midY = frame.midY
            if point.y < midY {
                insertionIndex = i
                break
            }
        }

        currentDropTarget = DropTarget(sectionId: hitSectionId, insertionIndex: insertionIndex)
    }
}

struct SectionFrameKey: Hashable {
    let sectionId: String?
}
