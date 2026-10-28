import AppKit
import SwiftUI

/// A colour that follows the window's light or dark appearance, and steps up to its `increased` pair while Increase
/// Contrast is on.
struct Adaptive: ShapeStyle {
    let light: Color
    let dark: Color
    var lightIncreased: Color?
    var darkIncreased: Color?

    func resolve(in environment: EnvironmentValues) -> Color {
        let isDark = environment.colorScheme == .dark
        if environment.colorSchemeContrast == .increased, let increased = isDark ? darkIncreased : lightIncreased {
            return increased
        }
        return isDark ? dark : light
    }
}

/// The website's look, for Settings: a cream page and cocoa text in light, the same palette at night in dark, with the
/// icon's yellow and pink for anything that is on or chosen. It is Settings' own: the notch keeps `Native`, pure black
/// in both. The values are the website's (`site/src/styles/global.css`).
enum Warm {
    /// The window behind everything.
    static let window = Adaptive(light: Color(hex: 0xFBF4E4), dark: Color(hex: 0x1C1611))
    /// A card of rows, a shade lighter than the window in dark and than the page in light.
    static let surface = Adaptive(light: Color(hex: 0xFFFBF2), dark: Color(hex: 0x271F18))
    /// Text and marks.
    static let ink = Adaptive(light: Color(hex: 0x2B2118), dark: Color(hex: 0xF5ECDD))
    /// Text that matters less than the title, such as a row's second line.
    static let secondary = Adaptive(
        light: Color(hex: 0x6B5B4D), dark: Color(hex: 0xBDAE9B),
        lightIncreased: Color(hex: 0x453829), darkIncreased: Color(hex: 0xDDD1BF)
    )
    /// The line between rows, and the edge of a card.
    static let hairline = Adaptive(
        light: Color(hex: 0x2B2118, opacity: 0.14), dark: Color(hex: 0xFFF4DC, opacity: 0.14),
        lightIncreased: Color(hex: 0x2B2118, opacity: 0.4), darkIncreased: Color(hex: 0xFFF4DC, opacity: 0.45)
    )
    /// A track a choice or a switch sits in.
    static let track = Adaptive(
        light: Color(hex: 0x2B2118, opacity: 0.07), dark: Color(hex: 0xFFF4DC, opacity: 0.09),
        lightIncreased: Color(hex: 0x2B2118, opacity: 0.12), darkIncreased: Color(hex: 0xFFF4DC, opacity: 0.16)
    )
    /// A switch that is off, a shade darker than `track`; with Increase Contrast it is 3:1 against the card.
    static let off = Adaptive(
        light: Color(hex: 0x2B2118, opacity: 0.14), dark: Color(hex: 0xFFF4DC, opacity: 0.18),
        lightIncreased: Color(hex: 0x2B2118, opacity: 0.5), darkIncreased: Color(hex: 0xFFF4DC, opacity: 0.38)
    )
    /// The edge of anything yellow: a chosen option, an on switch or a button. On the cream page yellow alone is 1.2:1
    /// against its track, so a thin ink edge gives the chosen state a boundary. In dark it is 9:1 and needs none.
    static let accentEdge = Adaptive(
        light: Color(hex: 0x2B2118, opacity: 0.35), dark: Color(hex: 0x2B2118, opacity: 0),
        lightIncreased: Color(hex: 0x2B2118, opacity: 0.6)
    )
    /// The hard edge under a quiet button, like the website's.
    static let lip = Adaptive(light: Color(hex: 0x2B2118, opacity: 0.14), dark: Color(hex: 0xFFF4DC, opacity: 0.16))

    /// The accents: yellow for anything on or chosen, and all three for the cards' icon tiles, as on the website. Text
    /// on any of them is `onAccent`, cocoa in light and dark.
    static let yellow = Color(hex: 0xFFD34E)
    static let yellowDeep = Color(hex: 0xE8B72B)
    static let pink = Color(hex: 0xFF7DB4)
    static let sky = Color(hex: 0xBCE0F2)
    static let onAccent = Color(hex: 0x2B2118)

    /// The corner radius of a card, and of the notch preview's wallpaper.
    static let cardRadius: CGFloat = 22
    /// How far a button or a chosen option stands off the surface, which it loses when pressed.
    static let lipDepth: CGFloat = 3

    /// The wallpaper the notch preview sits on, the website's three accents.
    static let wallpaper = LinearGradient(
        colors: [Color(hex: 0xFFE38A), Color(hex: 0xFF9FC9), Color(hex: 0xA9D6EE)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// The window's own fill for AppKit, so it is never white or black for a frame before SwiftUI draws.
    static let windowFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0x1C / 255, green: 0x16 / 255, blue: 0x11 / 255, alpha: 1)
            : NSColor(srgbRed: 0xFB / 255, green: 0xF4 / 255, blue: 0xE4 / 255, alpha: 1)
    }
}
