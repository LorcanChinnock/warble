#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// What the notch panel shows.
public enum NotchState: String, CaseIterable, Sendable {
    /// Nothing is playing and nothing needs the user's attention: nothing is drawn.
    case hidden
    /// Something is playing, or a Doctor check failed, and the pointer is elsewhere: the notch widened by a wing on each side.
    case resting
    /// Hovered or clicked: the full card with the art and room for the controls.
    case expanded

    /// How far `hover` has opened the notch while something is playing. Pinned draws as Expanded.
    public init(_ hover: HoverState) {
        switch hover {
        case .resting: self = .resting
        case .expanded, .pinned: self = .expanded
        }
    }
}

/// What Expanded holds, which sets how far it reaches down.
public enum NotchCard: Sendable {
    /// What's playing and its controls.
    case player
    /// The Doctor's checks, each with its fix.
    case doctor
}

/// Where the notch panel sits. All rects are in AppKit space.
public enum NotchLayout {
    /// The camera housing's bottom corner radius, as a fraction of its height. The hardware's radius and height are both
    /// a fixed number of pixels, so the ratio holds at every scale in System Settings › Displays, where a fixed number of
    /// points would round the corners more the larger the text. 12 points on a 15-inch MacBook Air's 37.5-point housing
    /// at More Space.
    public static let cornerRatio: CGFloat = 0.32
    /// The space around the art and the play-state bars in a resting wing, as a fraction of the housing's height.
    public static let insetRatio: CGFloat = 0.16
    /// How far Expanded reaches below the camera housing: the art beside three lines of text, then the position, the
    /// controls and the volume.
    public static let expandedDrop: CGFloat = 160
    /// How far Expanded reaches with the Doctor's card: a heading, then a line or two for each check and its fix.
    public static let doctorDrop: CGFloat = 220
    /// Room either side of the notch once expanded, for the art beside the text. Measured from the notch, so the card
    /// keeps its proportion to each Mac's camera housing.
    public static let expandedWing: CGFloat = 70

    /// The radius of the housing's bottom corners, which Hidden and Resting draw too.
    public static func cornerRadius(notch: CGRect) -> CGFloat {
        notch.height * cornerRatio
    }

    /// The space around the art and the play-state bars in a resting wing, the same on every side.
    public static func inset(notch: CGRect) -> CGFloat {
        notch.height * insetRatio
    }

    /// Room either side of the notch while resting: a square as tall as the housing, which holds the art on the left
    /// and the play-state bars on the right with `inset(notch:)` all round.
    public static func wing(notch: CGRect) -> CGFloat {
        notch.height
    }

    /// The panel's frame in `state` over `notch`, the camera housing, or `nil` when nothing is drawn. `card` is what
    /// Expanded holds.
    public static func frame(_ state: NotchState, notch: CGRect, card: NotchCard = .player) -> CGRect? {
        switch state {
        case .hidden:
            nil
        case .resting:
            CGRect(x: notch.minX - wing(notch: notch), y: notch.minY, width: notch.width + 2 * wing(notch: notch), height: notch.height)
        case .expanded:
            CGRect(x: notch.minX - expandedWing, y: notch.minY - drop(card), width: notch.width + 2 * expandedWing, height: notch.height + drop(card))
        }
    }

    /// The window that holds a shape drawn at `frame`, grown out to whole points. AppKit snaps a window to whole points by
    /// moving its origin down and keeping its width, which would put a housing at a half-point x half a point to the left;
    /// growing both edges keeps the window centred on the housing, so the shape drawn in its middle sits exactly over it.
    public static func window(for frame: CGRect) -> CGRect {
        frame.integral
    }

    private static func drop(_ card: NotchCard) -> CGFloat {
        card == .doctor ? doctorDrop : expandedDrop
    }

    /// Where the pointer counts as on the notch in `state`, for `HoverIntent`: only the camera housing while resting, so
    /// a pointer crossing the wings on its way to a menu bar item doesn't open it, and the whole panel once it's open.
    public static func hoverArea(_ state: NotchState, notch: CGRect, card: NotchCard = .player) -> CGRect? {
        state == .resting ? notch : frame(state, notch: notch, card: card)
    }
}
