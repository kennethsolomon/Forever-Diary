import SwiftUI

struct WaveformView: View {
    let audioLevels: [Float]
    let isActive: Bool

    @State private var idlePulse = false

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 4
    private let minHeight: CGFloat = 8
    private let maxHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<audioLevels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color("accentBright"))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .opacity(isActive ? 1.0 : (idlePulse ? 0.6 : 0.3))
            }
        }
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: audioLevels)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: idlePulse)
        .onAppear {
            idlePulse = true
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard index < audioLevels.count else { return minHeight }
        let level = CGFloat(audioLevels[index])
        return minHeight + (maxHeight - minHeight) * level
    }
}
