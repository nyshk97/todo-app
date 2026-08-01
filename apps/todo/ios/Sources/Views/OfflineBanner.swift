import SwiftUI

struct OfflineBanner: View {
    let isOnline: Bool
    let pendingCount: Int
    let syncError: String?

    private var colors: AppColors { Theme.current }

    var body: some View {
        if !isOnline || pendingCount > 0 || syncError != nil {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.caption)
                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(colors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(colors.listBackground.opacity(isOnline ? 0.9 : 1.0))
        }
    }

    private var iconName: String {
        if isOnline, syncError != nil { return "exclamationmark.triangle" }
        return isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash"
    }

    private var text: String {
        if isOnline, let syncError { return syncError }
        switch (isOnline, pendingCount) {
        case (false, 0): return "Offline"
        case (false, let count): return "Offline · \(count) pending"
        case (true, let count): return "\(count) pending sync"
        }
    }
}
