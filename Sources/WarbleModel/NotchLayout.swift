#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// What the notch panel shows.
public enum NotchState: String, CaseIterable, Sendable {
    /// Nothing is playing and nothing needs the user's attention, and the housing doesn't answer a hover: nothing is drawn.
    case hidden
    /// Nothing is playing and nothing needs the user's attention: the panel covers the camera housing exactly and shows
    /// nothing, black on a real housing and on a virtual one set to Always, and clear on any other virtual one, so a
    /// hover can open the idle card.
    case idle
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

    /// How far `hover` has opened the notch, given whether anything is playing, whether a Doctor check failed, what
    /// the housing does on a hover while Idle, and whether it stays drawn then (`NotchHousing.isAlwaysShown`).
    public init(_ hover: HoverState, isPlaying: Bool, needsAttention: Bool, idleHover: IdleHover, isAlwaysShown: Bool = false) {
        if isPlaying || needsAttention {
            self.init(hover)
        } else if idleHover == .nothing {
            self = isAlwaysShown ? .idle : .hidden
        } else {
            self = hover == .resting ? .idle : .expanded
        }
    }
}

/// What the camera housing does when the pointer rests on it while nothing is playing, from Settings › Notch.
public enum IdleHover: String, CaseIterable, Sendable {
    /// Opens the idle card: the last track played and a button to resume it.
    case lastPlayed
    /// Nothing: Warble stays out of sight until something plays.
    case nothing
}

/// What Expanded holds, which sets how far it reaches down.
public enum NotchCard: Sendable {
    /// What's playing and its controls.
    case player
    /// The Doctor's checks, each with its fix.
    case doctor
    /// While Idle: the last track played and a button to resume it, or a line saying nothing has played yet.
    case idle

    /// What Expanded holds: the checks when asked for, what's playing, the checks again when one failed with nothing
    /// playing, and otherwise the idle card.
    public init(isPlaying: Bool, needsAttention: Bool, showsDoctor: Bool) {
        if showsDoctor {
            self = .doctor
        } else if isPlaying {
            self = .player
        } else {
            self = needsAttention ? .doctor : .idle
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
    /// The space around the art and the play-state bars in a resting wing, as a fraction of the housing's height.
    public static let insetRatio: CGFloat = 0.16
    /// How far Expanded reaches below the camera housing: the art beside three lines of text, then the position, the
    /// controls and the volume.
    public static let expandedDrop: CGFloat = 160
    /// How far Expanded reaches with the Doctor's card: a heading, then a line or two for each check and its fix.
    public static let doctorDrop: CGFloat = 220
    /// How far the idle card reaches: the art beside three short lines, with no controls below.
    public static let idleDrop: CGFloat = 76
    /// Room either side of the notch once expanded, for the art beside the text. Measured from the notch, so the card
    /// keeps its proportion to each Mac's camera housing.
    public static let expandedWing: CGFloat = 70

    /// The radius of the housing's bottom corners, which Hidden, Idle and Resting draw too.
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
        case .idle:
            notch
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
        switch card {
        case .player: expandedDrop
        case .doctor: doctorDrop
        case .idle: idleDrop
        }
    }

    /// Where the pointer counts as on the notch in `state`, for `HoverIntent`: only the camera housing while Idle or
    /// resting, so a pointer crossing the wings or the menu bar on its way to a menu bar item doesn't open it, and the
    /// whole panel once it's open.
    public static func hoverArea(_ state: NotchState, notch: CGRect, card: NotchCard = .player) -> CGRect? {
        state == .resting || state == .idle ? notch : frame(state, notch: notch, card: card)
    }
}
