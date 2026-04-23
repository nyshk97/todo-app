import SwiftUI

struct SectionFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [SectionFrameKey: CGRect] = [:]

    static func reduce(value: inout [SectionFrameKey: CGRect], nextValue: () -> [SectionFrameKey: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TaskFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: TaskFrameInfo] = [:]

    static func reduce(value: inout [String: TaskFrameInfo], nextValue: () -> [String: TaskFrameInfo]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
