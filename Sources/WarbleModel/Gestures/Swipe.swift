import Foundation

/// A trackpad gesture over the notch, which goes one way at most: up and down changes the volume, and left and right
/// skips once. It decides the way from the gesture's first few points, so a scroll that drifts sideways never skips and a
/// swipe that drifts up never changes the volume. It waits on events, not on time, so it has no deadline.
public struct Swipe: Equatable, Sendable {
    /// Where a scroll event falls in its gesture, from `NSEvent.phase` and `momentumPhase`.
    public enum Phase: Equatable, Sendable {
        /// The fingers touched or began to move, which starts a new gesture.
        case began
        case changed
        /// The fingers lifted.
        case ended
        /// The scroll coasting on after the fingers lifted.
        case momentum
    }

    /// What one scroll event of the gesture does.
    public enum Outcome: Equatable, Sendable {
        /// Change the volume by this much vertical scroll, as `NSEvent.scrollingDeltaY` reports it.
        case volume(Double)
        case skip(PlaybackCommand)
        case nothing
    }

    enum Axis: Equatable, Sendable {
        case undecided, vertical, horizontal
    }

    /// How far, in points, a gesture moves before Warble decides which way it goes: far enough to tell, too little to see.
    public static let lockDistance = 6.0
    /// How far, in points, a swipe goes before it skips: a short flick, but more than a scroll drifts sideways.
    public static let skipDistance = 50.0

    var axis: Axis?
    /// What the gesture has moved so far: both ways until it's decided, then only sideways.
    var across = 0.0
    var down = 0.0
    var skipped = false

    public init() {}

    /// Takes the next scroll event of a gesture. `inverted` is natural scrolling, which flips the deltas, so moving the
    /// fingers left skips forward either way, as swiping to the next page does.
    public mutating func handle(across dx: Double, down dy: Double, phase: Phase, inverted: Bool) -> Outcome {
        if phase == .began || axis == nil {
            // A gesture already under way when the pointer arrived starts from here, but a coast never decides anything.
            guard phase != .momentum else { return .volume(dy) }
            axis = .undecided
            across = 0
            down = 0
            skipped = false
        }
        switch axis {
        case .vertical:
            return .volume(dy)
        case .horizontal:
            // Only the fingers skip; the coast after them doesn't.
            return phase == .momentum ? .nothing : skip(dx, inverted: inverted)
        default:
            across += dx
            down += dy
            if max(abs(across), abs(down)) >= Self.lockDistance || phase != .began && phase != .changed {
                // Decided, or the gesture ended first: what it held back goes to the side it took.
                if abs(across) > abs(down) {
                    axis = .horizontal
                    let moved = across
                    across = 0
                    return skip(moved, inverted: inverted)
                }
                axis = .vertical
                return .volume(down)
            }
            return .nothing
        }
    }

    private mutating func skip(_ dx: Double, inverted: Bool) -> Outcome {
        guard !skipped else { return .nothing }
        across += dx
        guard abs(across) >= Self.skipDistance else { return .nothing }
        skipped = true
        // Without natural scrolling, fingers moving left report a positive delta.
        let left = inverted ? -across : across
        return .skip(left > 0 ? .nextTrack : .previousTrack)
    }
}
