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
    /// The pointer has stayed on the notch: Resting grown down to show the title, artist and progress.
    case peek
    /// Clicked, or hovered for longer: the full card with the art and room for the controls.
    case expanded

    /// How far `hover` has opened the notch while something is playing. Pinned draws as Expanded.
    public init(_ hover: HoverState) {
        switch hover {
        case .resting: self = .resting
        case .peeking: self = .peek
        case .expanded, .pinned: self = .expanded
        }
    }
}

/// Where the notch panel sits. All rects are in AppKit space.
public enum NotchLayout {
    /// Room either side of the notch for the art and the play-state bars.
    public static let wing: CGFloat = 50
    /// How far Peek reaches below the camera housing: the title, the artist and a thin progress line.
    public static let peekDrop: CGFloat = 44
    /// How far Expanded reaches below the camera housing: the art beside three lines of text, then the position, the
    /// controls and the volume.
    public static let expandedDrop: CGFloat = 160
    /// Room either side of the notch once expanded, for the art beside the text. Measured from the notch, so the card
    /// keeps its proportion to each Mac's camera housing.
    public static let expandedWing: CGFloat = 70

    /// The panel's frame in `state` over `notch`, the camera housing, or `nil` when nothing is drawn.
    public static func frame(_ state: NotchState, notch: CGRect) -> CGRect? {
        switch state {
        case .hidden:
            nil
        case .resting:
            CGRect(x: notch.minX - wing, y: notch.minY, width: notch.width + 2 * wing, height: notch.height)
        case .peek:
            CGRect(x: notch.minX - wing, y: notch.minY - peekDrop, width: notch.width + 2 * wing, height: notch.height + peekDrop)
        case .expanded:
            CGRect(x: notch.minX - expandedWing, y: notch.minY - expandedDrop, width: notch.width + 2 * expandedWing, height: notch.height + expandedDrop)
        }
    }

    /// Where the pointer counts as on the notch in `state`, for `HoverIntent`: only the camera housing while resting, so
    /// a pointer crossing the wings on its way to a menu bar item doesn't open it, and the whole panel once it's open.
    public static func hoverArea(_ state: NotchState, notch: CGRect) -> CGRect? {
        state == .resting ? notch : frame(state, notch: notch)
    }
}
