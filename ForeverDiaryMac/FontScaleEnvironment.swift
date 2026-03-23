import SwiftUI

// MARK: - Environment Key

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var fontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

// MARK: - Scaled Font Modifier

struct ScaledFont: ViewModifier {
    @Environment(\.fontScale) private var fontScale

    let baseSize: CGFloat
    let design: Font.Design
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(size: baseSize * fontScale, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(size: CGFloat, design: Font.Design = .default, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(baseSize: size, design: design, weight: weight))
    }
}
