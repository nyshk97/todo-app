import SwiftUI
import UIKit

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

    weak var scrollView: UIScrollView?

    private var autoScrollTask: Swift.Task<Void, Never>?
    private var autoScrollSpeed: CGFloat = 0
    private let autoScrollThreshold: CGFloat = 60
    private let autoScrollMaxSpeed: CGFloat = 400

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
        updateAutoScroll()
    }

    struct DropResult {
        let taskId: String
        let sourceSectionId: String?
        let target: DropTarget
    }

    func endDrag() -> DropResult? {
        stopAutoScroll()
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
        stopAutoScroll()
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

    // MARK: - Auto-scroll

    private func updateAutoScroll() {
        guard let sv = scrollView, isActive else {
            stopAutoScroll()
            return
        }
        let topEdge = sv.contentOffset.y
        let bottomEdge = topEdge + sv.bounds.height

        if dragLocation.y < topEdge + autoScrollThreshold {
            let dist = max(0, dragLocation.y - topEdge)
            let factor = 1 - (dist / autoScrollThreshold)
            autoScrollSpeed = -autoScrollMaxSpeed * factor
            ensureAutoScrollRunning()
        } else if dragLocation.y > bottomEdge - autoScrollThreshold {
            let dist = max(0, bottomEdge - dragLocation.y)
            let factor = 1 - (dist / autoScrollThreshold)
            autoScrollSpeed = autoScrollMaxSpeed * factor
            ensureAutoScrollRunning()
        } else {
            stopAutoScroll()
        }
    }

    private func ensureAutoScrollRunning() {
        guard autoScrollTask == nil else { return }
        autoScrollTask = Swift.Task { @MainActor [weak self] in
            while let self, !Swift.Task.isCancelled, self.autoScrollSpeed != 0, self.isActive {
                self.tickAutoScroll()
                try? await Swift.Task.sleep(for: .milliseconds(16))
            }
            self?.autoScrollTask = nil
        }
    }

    private func tickAutoScroll() {
        guard let sv = scrollView, autoScrollSpeed != 0 else { return }
        let dt: CGFloat = 1.0 / 60.0
        let delta = autoScrollSpeed * dt
        let currentY = sv.contentOffset.y
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        let newY = max(0, min(currentY + delta, maxOffset))
        let actualDelta = newY - currentY

        if actualDelta == 0 {
            stopAutoScroll()
            return
        }

        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: newY), animated: false)
        dragLocation.y += actualDelta
        recomputeDropTarget()
    }

    private func stopAutoScroll() {
        autoScrollSpeed = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
}

struct SectionFrameKey: Hashable {
    let sectionId: String?
}
