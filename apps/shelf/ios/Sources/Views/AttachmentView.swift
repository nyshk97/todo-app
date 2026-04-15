import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let viewModel: ShelfViewModel
    var onDelete: (() -> Void)?

    var body: some View {
        if attachment.isImage {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: viewModel.attachmentURL(id: attachment.id)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        fileRow
                    default:
                        ProgressView()
                            .frame(height: 100)
                    }
                }

                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.system(size: 20))
                    }
                    .padding(4)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .font(.caption)
                    .foregroundStyle(Theme.textQuaternary)

                Link(destination: viewModel.attachmentURL(id: attachment.id)) {
                    Text(attachment.filename)
                        .font(.caption)
                        .foregroundStyle(Theme.accentBright)
                        .lineLimit(1)
                }

                Text("(\(formatFileSize(attachment.size)))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textQuaternary)

                Spacer()

                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textQuaternary)
                    }
                }
            }
            .padding(8)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var fileRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .foregroundStyle(Theme.textQuaternary)
            Text(attachment.filename)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(8)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
