#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// What the notch panel shows.
public enum NotchState: String, CaseIterable, Sendable {
    /// Nothing is playing: nothing is drawn.
    case hidden
    /// Something is playing and the pointer is elsewhere: the notch widened by a wing on each side.
    case resting
}

/// Where the notch panel sits. All rects are in AppKit space.
public enum NotchLayout {
    /// Room either side of the notch for the art and the play-state bars.
    public static let wing: CGFloat = 50

    /// The panel's frame in `state` over `notch`, the camera housing, or `nil` when nothing is drawn.
    public static func frame(_ state: NotchState, notch: CGRect) -> CGRect? {
        switch state {
        case .hidden:
            nil
        case .resting:
            CGRect(x: notch.minX - wing, y: notch.minY, width: notch.width + 2 * wing, height: notch.height)
        }
    }
}
