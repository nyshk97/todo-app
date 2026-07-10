import SwiftUI
import UIKit

/// タスクの D&D を UIKit の UILongPressGestureRecognizer で駆動する。
/// SwiftUI の LongPress→Drag シーケンスジェスチャーは行の上のタッチを主張して
/// ScrollView のスクロールをブロックするが、UIKit のロングプレスはスクロールの
/// パンと failure requirement で調停される（指が動けばスクロール、止まればドラッグ）。
struct TaskDragRecognizer: UIViewRepresentable {
    let dragController: DragController
    let projectId: String
    let onDrop: (DragController.DropResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(dragController: dragController, projectId: projectId, onDrop: onDrop)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(anchor: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.dragController = dragController
        context.coordinator.projectId = projectId
        context.coordinator.onDrop = onDrop
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(anchor: uiView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var dragController: DragController
        var projectId: String
        var onDrop: (DragController.DropResult) -> Void

        // anchor は "project" 座標空間の view を background として同サイズで
        // 配置されるため、location(in: anchor) がそのまま taskFrames と同じ座標系になる
        private weak var anchorView: UIView?
        private weak var attachedScrollView: UIScrollView?
        private var recognizer: UILongPressGestureRecognizer?

        init(
            dragController: DragController,
            projectId: String,
            onDrop: @escaping (DragController.DropResult) -> Void
        ) {
            self.dragController = dragController
            self.projectId = projectId
            self.onDrop = onDrop
        }

        func attachIfNeeded(anchor: UIView) {
            anchorView = anchor
            guard let scrollView = Self.findEnclosingScrollView(from: anchor) else { return }
            dragController.scrollView = scrollView
            guard attachedScrollView !== scrollView else { return }

            if let old = recognizer {
                old.view?.removeGestureRecognizer(old)
            }
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.4
            longPress.delegate = self
            scrollView.addGestureRecognizer(longPress)
            recognizer = longPress
            attachedScrollView = scrollView
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let anchor = anchorView else { return }
            let point = gesture.location(in: anchor)

            switch gesture.state {
            case .began:
                guard !dragController.isActive,
                      let hit = taskHit(at: point) else { return }
                dragController.startDrag(
                    taskId: hit.key,
                    projectId: projectId,
                    sourceSectionId: hit.value.sectionId,
                    touchOffset: CGSize(
                        width: point.x - hit.value.frame.minX,
                        height: point.y - hit.value.frame.minY
                    ),
                    ghostSize: hit.value.frame.size,
                    initialLocation: point
                )
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .changed:
                guard dragController.isActive else { return }
                dragController.updateLocation(point)
            case .ended:
                guard dragController.isActive else { return }
                if let result = dragController.endDrag() {
                    onDrop(result)
                }
            case .cancelled, .failed:
                dragController.cancelDrag()
            default:
                break
            }
        }

        private func taskHit(at point: CGPoint) -> (key: String, value: TaskFrameInfo)? {
            dragController.taskFrames
                .first(where: { $0.value.frame.contains(point) })
                .map { (key: $0.key, value: $0.value) }
        }

        // タスク行の上で始まったタッチだけ受け取る。セクションヘッダー（contextMenu の
        // ロングプレス）や追加ボタンの上では認識を開始せず、既存の操作と競合させない
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let anchor = anchorView else { return false }
            return taskHit(at: touch.location(in: anchor)) != nil
        }

        private static func findEnclosingScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            while let v = current {
                if let sv = v as? UIScrollView { return sv }
                current = v.superview
            }
            return nil
        }
    }
}
