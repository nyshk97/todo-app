import SwiftUI

struct OfflineBanner: View {
    let isOnline: Bool
    let pendingCount: Int

    var body: some View {
        if !isOnline || pendingCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
                    .font(.caption)
                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isOnline ? Theme.bgPanel : Theme.orange.opacity(0.15))
        }
    }

    private var text: String {
        switch (isOnline, pendingCount) {
        case (false, 0): return "オフライン"
        case (false, let n): return "オフライン · \(n)件未同期"
        case (true, let n): return "\(n)件同期中…"
        }
    }
}
