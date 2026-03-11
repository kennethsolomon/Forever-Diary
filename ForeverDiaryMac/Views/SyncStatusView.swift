import SwiftUI

struct SyncStatusView: View {
    let isSyncing: Bool
    let hasError: Bool

    var body: some View {
        Image(systemName: isSyncing
              ? "arrow.triangle.2.circlepath.icloud"
              : (hasError ? "exclamationmark.icloud" : "checkmark.icloud"))
            .foregroundStyle(hasError ? .red : .secondary)
            .symbolEffect(.pulse, isActive: isSyncing)
    }
}
