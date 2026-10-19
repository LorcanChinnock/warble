import SwiftUI
import WarbleCore

/// Warble's look: pure black that merges with the camera housing, the system font, and white marks with grey for
/// anything secondary. No accent colour. The prototype is the "A · Native" artboard of the Warble notch directions canvas.
enum Native {
    /// The panel's fill, the same black as the notch whatever the appearance.
    static let panel = Color.black
    /// Text and marks that matter less than the title, such as the artist.
    static let secondary = ContrastAware(standard: Color(white: 0.6), increased: Color(white: 0.8))
    /// Bottom corner radius of the notch at rest. Expanded rounds more as it grows.
    static let restingRadius: CGFloat = 12

    /// Space above and below the art in a resting wing.
    static let restingInset: CGFloat = 6

    static func radius(_ state: NotchState) -> CGFloat {
        switch state {
        case .hidden, .resting: restingRadius
        case .expanded: 24
        }
    }

    /// The change of shape between states. No bounce: the panel's frame is only as big as the larger state, so an
    /// overshoot would be clipped.
    static let morph = Animation.smooth(duration: 0.25)
    /// The content's cross-fade between states, which is all that moves while Reduce Motion is on.
    static let fade = Animation.easeInOut(duration: 0.2)
}
