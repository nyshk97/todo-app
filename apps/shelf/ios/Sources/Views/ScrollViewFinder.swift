import SwiftUI
import UIKit

struct ScrollViewFinder: UIViewRepresentable {
    let onFind: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            if let scrollView = Self.findEnclosingScrollView(from: view) {
                onFind(scrollView)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = Self.findEnclosingScrollView(from: uiView) {
                onFind(scrollView)
            }
        }
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
