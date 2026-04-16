import SwiftUI

struct SectionReorderSheet: View {
    let viewModel: ShelfViewModel
    let projectId: String
    @Environment(\.dismiss) private var dismiss

    @State private var orderedSections: [Section] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedSections) { section in
                    Text(section.name)
                        .foregroundStyle(Theme.textPrimary)
                }
                .onMove { from, to in
                    orderedSections.move(fromOffsets: from, toOffset: to)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("セクションを並び替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        let ids = orderedSections.map(\.id)
                        Swift.Task {
                            await viewModel.reorderSections(projectId: projectId, sectionIds: ids)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            orderedSections = viewModel.sectionsFor(projectId: projectId)
        }
    }
}
