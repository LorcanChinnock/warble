import SwiftUI

/// A colour that steps up to `increased` while Increase Contrast is on.
struct ContrastAware: ShapeStyle {
    let standard: Color
    let increased: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorSchemeContrast == .increased ? increased : standard
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension Color {
    /// The icon's yellow, `#F6C744`, for what's on or chosen in Warble's windows: a switch that's on, a chosen segment.
    /// Never for text. The notch has no accent colour (`Native`).
    static let warbleYellow = Color("Yellow")

    /// A darker gold, `#BE8E14`, for a switch that's on with Increase Contrast in the light appearance, where the yellow
    /// is about 1.6:1 against the window. It's for fills without text: a label on it would be too faint either way.
    static let warbleGold = Color(hex: 0xBE8E14)
}
