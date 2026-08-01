import SwiftUI

struct ToastOverlay: View {
    @Bindable var viewModel: ShelfViewModel

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ForEach(viewModel.toasts) { toast in
                ToastBanner(toast: toast, onDismiss: {
                    withAnimation { viewModel.dismissToast(toast.id) }
                }, onRetry: {
                    viewModel.dismissToast(toast.id)
                    if let retry = toast.retry {
                        Swift.Task { await retry() }
                    }
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 100)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.25), value: viewModel.toasts.count)
    }
}

private struct ToastBanner: View {
    let toast: ToastItem
    let onDismiss: () -> Void
    let onRetry: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(2)

            Spacer()

            if toast.retry != nil {
                Button("再試行") { onRetry() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0x71/255.0, green: 0x70/255.0, blue: 0xFF/255.0))
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if appeared { onDismiss() }
            }
        }
        .onDisappear { appeared = false }
    }
}
