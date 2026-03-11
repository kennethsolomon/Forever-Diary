import SwiftUI

struct SyncStatusView: View {
    let isSyncing: Bool
    let hasError: Bool
    let isConnected: Bool

    private var icon: String {
        if !isConnected { return "wifi.slash" }
        if isSyncing { return "arrow.triangle.2.circlepath.icloud.fill" }
        if hasError  { return "exclamationmark.icloud.fill" }
        return "checkmark.icloud.fill"
    }

    private var label: String {
        if !isConnected { return "Offline" }
        if isSyncing { return "Syncing" }
        if hasError  { return "Sync error" }
        return "Synced"
    }

    private var tint: Color {
        if !isConnected { return Color("textSecondary") }
        if hasError  { return Color("destructive") }
        if isSyncing { return Color("accentBright") }
        return Color("textSecondary")
    }

    private var bgOpacity: Double {
        isSyncing || hasError ? 0.12 : 0.07
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .symbolEffect(.pulse, isActive: isSyncing)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(bgOpacity))
        )
        .animation(.easeInOut(duration: 0.25), value: isSyncing)
        .animation(.easeInOut(duration: 0.25), value: hasError)
        .animation(.easeInOut(duration: 0.25), value: isConnected)
    }
}
