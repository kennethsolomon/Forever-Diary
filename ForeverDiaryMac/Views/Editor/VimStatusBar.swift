import SwiftUI

struct VimStatusBar: View {
    let mode: VimMode
    let pendingCommand: String

    private var modeColor: Color {
        switch mode {
        case .normal: return Color("textSecondary")
        case .insert: return Color("habitComplete")
        case .visual, .visualLine: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("-- \(mode.displayName) --")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(modeColor)

            if !pendingCommand.isEmpty {
                Text(pendingCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color("textSecondary"))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color("surfaceCard"))
    }
}
