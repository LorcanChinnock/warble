import Foundation

/// The first-run demo of the notch: it rests with a preview track, opens, then goes back to Idle with a hint below it.
/// Like `IdleAfterPause` it holds no timer: after each call the owner arms one for `deadline`, if any, and calls
/// `advance(to:)` when it fires.
public struct NotchDemo: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// The wings, with the preview track.
        case resting
        /// The player's card, with the preview track.
        case expanded
        /// Idle, with "Hover here to see what's playing" in a strip below.
        case hint

        /// How long the step shows, from `NotchMotion`.
        var duration: TimeInterval {
            switch self {
            case .resting: NotchMotion.demoResting
            case .expanded: NotchMotion.demoExpanded
            case .hint: NotchMotion.demoHint
            }
        }

        var next: Step? {
            switch self {
            case .resting: .expanded
            case .expanded: .hint
            case .hint: nil
            }
        }
    }

    /// The step showing, or `nil` before it starts and after it ends.
    public internal(set) var step: Step?
    /// When the step ends and the next shows, or `nil` while no step shows.
    public internal(set) var deadline: Date?
    /// When it started, which the preview track's position runs on from.
    public internal(set) var startedAt: Date?

    public init() {}

    public var isRunning: Bool { step != nil }

    /// Whether the preview track is on show: the steps with a player in them.
    public var showsTrack: Bool { step == .resting || step == .expanded }

    mutating func start(at date: Date) {
        startedAt = date
        show(.resting, at: date)
    }

    /// Applies every deadline due by `date`. Returns whether the demo ended.
    mutating func advance(to date: Date) -> Bool {
        while let due = deadline, due <= date, let step {
            guard let next = step.next else {
                end()
                return true
            }
            show(next, at: due)
        }
        return false
    }

    /// Stops it at once, for a touch or something playing.
    mutating func end() {
        step = nil
        deadline = nil
    }

    private mutating func show(_ step: Step, at date: Date) {
        self.step = step
        deadline = date + step.duration
    }
}
