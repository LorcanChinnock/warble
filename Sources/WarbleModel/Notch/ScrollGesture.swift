import Foundation

/// Turns the scroll events over a notch into one thing per gesture: up and down sets the volume, a slow slide sideways
/// moves through the song, and a quick flick sideways skips. A gesture keeps the direction it starts in, so a slide that
/// drifts doesn't change the volume as well.
public struct ScrollGesture: Sendable {
    public enum Phase: Equatable, Sendable {
        case began, changed, ended
        /// The coasting after fingers lift, which nothing acts on.
        case momentum
        /// The phase an event reports: coasting wins over everything, then a gesture beginning, then it ending or being
        /// cancelled, and anything else is it moving on. A mouse wheel reports no phase, so it is always `changed`.
        public init(coasting: Bool, began: Bool, endedOrCancelled: Bool) {
            self = if coasting {
                .momentum
            } else if began {
                .began
            } else if endedOrCancelled {
                .ended
            } else {
                .changed
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// Up and down, as `NSEvent.scrollingDeltaY` reports it.
        case volume(Double)
        /// Seconds to move through the song, forward when positive.
        case scrub(TimeInterval)
        case skip(next: Bool)
    }

    /// Points a gesture moves before it picks up or down or sideways.
    static let lockDistance = 6.0
    /// Seconds of song per point a slide moves.
    static let secondsPerPoint = 0.2
    /// Above this speed, in points a second, a slide is on its way to a flick and stops moving through the song.
    static let scrubSpeedLimit = 700.0
    /// The speed a flick must reach, and the least it must travel, in points.
    static let flickSpeed = 1400.0
    static let flickDistance = 60.0
    /// The most often a slide moves the song, so a player that is slow to seek isn't sent every event.
    static let scrubInterval = 0.1

    private enum Axis { case vertical, horizontal }

    private var axis: Axis?
    private var seen = (x: 0.0, y: 0.0)
    private var travel = 0.0
    private var speed = 0.0
    private var peak = 0.0
    private var pending = 0.0
    private var last: TimeInterval?
    private var lastScrub: TimeInterval = -.infinity

    public init() {}

    /// What an event does. `precise` is a trackpad or Magic Mouse; a mouse wheel only sets the volume. `time` is the
    /// event's timestamp in seconds. A direction is as the fingers move, so `inverted` (natural scrolling) is applied here.
    public mutating func handle(dx: Double, dy: Double, precise: Bool, inverted: Bool, phase: Phase, at time: TimeInterval) -> Outcome? {
        guard precise else { return dy == 0 ? nil : .volume(dy) }
        if phase == .momentum { return nil }
        if phase == .began { self = ScrollGesture() }
        defer { last = time }

        let right = inverted ? dx : -dx
        switch axis {
        case nil:
            seen.x += right
            seen.y += dy
            if max(abs(seen.x), abs(seen.y)) >= Self.lockDistance {
                axis = abs(seen.y) > abs(seen.x) ? .vertical : .horizontal
                if axis == .vertical { return phase == .ended ? finish() : .volume(seen.y) }
                return slide(by: seen.x, phase: phase, at: time)
            }
        case .vertical:
            if dy != 0 { return .volume(dy) }
        case .horizontal:
            return slide(by: right, phase: phase, at: time)
        }
        return phase == .ended ? finish() : nil
    }

    private mutating func slide(by right: Double, phase: Phase, at time: TimeInterval) -> Outcome? {
        travel += right
        if let last, time > last {
            speed = 0.5 * speed + 0.5 * right / max(time - last, 0.004)
            if abs(speed) > abs(peak) { peak = speed }
        }
        if phase == .ended { return finish() }
        if abs(speed) < Self.scrubSpeedLimit {
            pending += right * Self.secondsPerPoint
        }
        guard pending != 0, time - lastScrub >= Self.scrubInterval else { return nil }
        defer { pending = 0; lastScrub = time }
        return .scrub(pending)
    }

    /// At the end: a flick skips, and a slide moves the song by what it hadn't yet.
    private mutating func finish() -> Outcome? {
        defer { self = ScrollGesture() }
        guard axis == .horizontal else { return nil }
        if abs(peak) >= Self.flickSpeed, abs(travel) >= Self.flickDistance {
            return .skip(next: travel > 0)
        }
        return pending == 0 ? nil : .scrub(pending)
    }
}
