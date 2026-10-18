import AppKit
import SwiftUI
import WarbleCore

extension EnvironmentValues {
    /// Settings › General › Text size, set at the root of every hosted view.
    @Entry var textSize = TextSize.standard
}

/// A system font that grows with Settings › General › Text size. Use `.font(.scaled(…))` for Warble's own interface text;
/// a plain `Font` stays the size it says, for anything that shows content, such as a track title drawn at a fixed size.
struct ScaledFont {
    let size: CGFloat
    var weight: Font.Weight?
    var design: Font.Design?

    static func scaled(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> ScaledFont {
        ScaledFont(size: size, weight: weight, design: design)
    }

    func resolved(_ textSize: TextSize) -> Font {
        .system(size: textSize.points(size), weight: weight, design: design)
    }

    /// For AppKit drawing, which can't read the environment.
    func points(_ textSize: TextSize) -> CGFloat { textSize.points(size) }
}

private struct ScaledFontModifier: ViewModifier {
    let font: ScaledFont
    @Environment(\.textSize) private var textSize

    func body(content: Content) -> some View {
        content.font(font.resolved(textSize))
    }
}

extension View {
    func font(_ font: ScaledFont) -> some View {
        modifier(ScaledFontModifier(font: font))
    }
}

/// A colour that steps up to `increased` while Increase Contrast is on.
struct ContrastAware: ShapeStyle {
    let standard: Color
    let increased: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorSchemeContrast == .increased ? increased : standard
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
