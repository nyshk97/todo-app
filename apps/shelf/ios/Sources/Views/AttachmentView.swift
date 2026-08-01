import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let viewModel: ShelfViewModel
    var onDelete: (() -> Void)?

    @State private var showPreview = false

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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showPreview = true
                            }
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
            .fullScreenCover(isPresented: $showPreview) {
                ImagePreviewView(url: viewModel.attachmentURL(id: attachment.id))
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

// MARK: - Image Preview

private struct ImagePreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1.0, min(lastScale * value, 5.0))
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale <= 1.0 {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1.0 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                case .failure:
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                default:
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding()
        }
    }
}
