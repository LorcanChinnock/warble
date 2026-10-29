#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// What the notch panel shows.
public enum NotchState: String, CaseIterable, Sendable {
    /// Nothing is playing, or the display shows a full-screen app: nothing is drawn, and the housing takes no hover.
    case hidden
    /// Nothing is playing, and the notch is one that stays: a real notch, or a virtual one that Settings keeps always. The
    /// housing's own shape, empty, which takes a hover so it can open `note`.
    case empty
    /// The pointer is on an empty notch: a small card that says nothing is playing, with no controls.
    case note
    /// The pointer is on an empty notch that remembers the last track: a small card with its art and title and a resume button.
    case recall
    /// Something is playing and the pointer is elsewhere: the notch widened by a wing on each side.
    case resting
    /// Hovered: the full card with the art and room for the controls.
    case expanded

    /// Whether the notch is open, as a card under the housing: the player, the note or the remembered track.
    public var isOpen: Bool { self == .expanded || self == .note || self == .recall }

    /// How far `hover` has opened the notch while something is playing.
    public init(_ hover: HoverState) {
        switch hover {
        case .resting: self = .resting
        case .expanded: self = .expanded
        }
    }

    /// How far `hover` has opened the notch, given whether anything is playing. With nothing playing there's nothing to
    /// open, so an open notch closes behind the housing.
    public init(_ hover: HoverState, isPlaying: Bool) {
        if isPlaying {
            self.init(hover)
        } else {
            self = .hidden
        }
    }
}

/// How big the card is that the notch opens into, which Settings chooses. Only the open card changes; Empty and Resting
/// stay the housing's size so they keep matching a real notch.
public enum CardSize: String, CaseIterable, Sendable {
    case small
    case standard
    case large

    /// How much of its standard size the open card is drawn at.
    public var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .standard: 1
        case .large: 1.2
        }
    }
}

/// Where the notch panel sits. All rects are in AppKit space.
public enum NotchLayout {
    /// The camera housing's bottom corner radius, as a fraction of its height. The hardware's radius and height are both
    /// a fixed number of pixels, so the ratio holds at every scale in System Settings › Displays, where a fixed number of
    /// points would round the corners more the larger the text. 12 points on a 15-inch MacBook Air's 37.5-point housing
    /// at More Space.
    public static let cornerRatio: CGFloat = 0.32
    /// How far the top corners flare outward into the screen's top edge, as a fraction of the housing's height, so it scales
    /// with the housing as `cornerRatio` does. 6 points on a 15-inch MacBook Air's 37.5-point housing at More Space.
    public static let topCornerRatio: CGFloat = 0.16
    /// The space around the art and the play-state bars in a resting wing, as a fraction of the housing's height.
    public static let insetRatio: CGFloat = 0.16
    /// How far Expanded reaches below the camera housing: the art beside three lines of text, then the position, the
    /// controls and the volume.
    public static let expandedDrop: CGFloat = 160
    /// Room either side of the notch once expanded, for the art beside the text. Measured from the notch, so the card
    /// keeps its proportion to each Mac's camera housing.
    public static let expandedWing: CGFloat = 70
    /// How far the note reaches below the housing: one line of text with room above and below.
    public static let noteDrop: CGFloat = 36
    /// How far the remembered track's card reaches below the housing: the art beside two lines, with room around them.
    public static let recallDrop: CGFloat = 72

    /// The radius of the housing's bottom corners, which Empty and Resting draw too.
    public static func cornerRadius(notch: CGRect) -> CGFloat {
        notch.height * cornerRatio
    }

    /// The radius of the top corners' outward flare, which every state draws.
    public static func topCornerRadius(notch: CGRect) -> CGFloat {
        notch.height * topCornerRatio
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

    /// The panel's frame in `state` over `notch`, the camera housing, or `nil` when nothing is drawn. `cardSize` scales
    /// Expanded alone, about the housing's bottom centre.
    public static func frame(_ state: NotchState, notch: CGRect, cardSize: CardSize = .standard) -> CGRect? {
        switch state {
        case .hidden:
            nil
        case .empty:
            notch
        case .note:
            CGRect(x: notch.minX - wing(notch: notch), y: notch.minY - noteDrop, width: notch.width + 2 * wing(notch: notch), height: notch.height + noteDrop)
        case .recall:
            CGRect(x: notch.minX - wing(notch: notch), y: notch.minY - recallDrop, width: notch.width + 2 * wing(notch: notch), height: notch.height + recallDrop)
        case .resting:
            CGRect(x: notch.minX - wing(notch: notch), y: notch.minY, width: notch.width + 2 * wing(notch: notch), height: notch.height)
        case .expanded:
            expandedFrame(notch: notch, cardSize: cardSize)
        }
    }

    /// The open card at its standard size scaled by `cardSize`, hanging from the top of the housing and centred on it.
    private static func expandedFrame(notch: CGRect, cardSize: CardSize) -> CGRect {
        let width = (notch.width + 2 * expandedWing) * cardSize.scale
        let height = (notch.height + expandedDrop) * cardSize.scale
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
    }

    /// The window that holds a shape drawn at `frame`, grown out to whole points. AppKit snaps a window to whole points by
    /// moving its origin down and keeping its width, which would put a housing at a half-point x half a point to the left;
    /// growing both edges keeps the window centred on the housing, so the shape drawn in its middle sits exactly over it.
    /// `flare` is the top corners' reach outside `frame` (`topCornerRadius(notch:)`), which the window holds on both sides.
    public static func window(for frame: CGRect, flare: CGFloat = 0) -> CGRect {
        frame.insetBy(dx: -flare, dy: 0).integral
    }

    /// Where the pointer counts as on the notch in `state`, for `HoverIntent`: only the camera housing while resting or empty, so a
    /// pointer crossing the wings or the menu bar on its way elsewhere doesn't open it, and the whole panel once it's open.
    public static func hoverArea(_ state: NotchState, notch: CGRect, cardSize: CardSize = .standard) -> CGRect? {
        switch state {
        case .resting: notch
        case .hidden: nil
        case .empty: notch
        case .expanded, .note, .recall: frame(state, notch: notch, cardSize: cardSize)
        }
    }
}
