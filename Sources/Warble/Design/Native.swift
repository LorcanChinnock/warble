import SwiftUI
import WarbleCore

/// Warble's look: pure black that merges with the camera housing, the system font, and white marks with grey for
/// anything secondary. No accent colour. The prototype is the "A · Native" artboard of the Warble notch directions canvas.
enum Native {
    /// The panel's fill, the same black as the notch whatever the appearance.
    static let panel = Color.black
    /// Text and marks that matter less than the title, such as the artist.
    static let secondary = ContrastAware(standard: Color(white: 0.6), increased: Color(white: 0.8))
    /// Bottom corner radius of the expanded card, rounder than the housing's as the card is larger.
    static let expandedRadius: CGFloat = 24

    /// Bottom corner radius of the notch over `notch`: the camera housing's own at rest, `expandedRadius` once open.
    static func radius(_ state: NotchState, notch: CGRect) -> CGFloat {
        switch state {
        case .hidden, .resting: NotchLayout.cornerRadius(notch: notch)
        case .expanded: expandedRadius
        }
    }

    /// The change of shape between states. No bounce: the panel's frame is only as big as the larger state, so an
    /// overshoot would be clipped.
    static let morph = Animation.smooth(duration: 0.25)
    /// The content's cross-fade between states, which is all that moves while Reduce Motion is on.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// The expanded card's glow in the artwork's colours, the one exception to the black, rises from its bottom corners
    /// and fades out before the top, so the top edge still merges with the housing.
    static let glowOpacity = 0.45
    /// How far up the card the glow reaches from each bottom corner, as a fraction of the card.
    static let glowReach = 0.8
    /// The glow's change of colour with the track, slow enough not to flash.
    static let glowChange = Animation.easeInOut(duration: 0.6)
    /// The solid border drawn instead of the glow while Increase Contrast is on.
    static let contrastBorder: CGFloat = 2
}
