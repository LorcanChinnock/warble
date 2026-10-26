import Foundation

/// What a first launch shows: the notch demo, then the welcome window, each once, then left alone for good.
public struct Onboarding: Feature {
    public enum Welcome: Equatable, Sendable {
        /// Not asked for in this launch.
        case notShown
        /// Waiting for the demo to end.
        case waiting
        /// Asked for and open.
        case showing
        /// Closed, so it isn't asked for again.
        case closed
    }

    public internal(set) var welcome = Welcome.notShown
    public internal(set) var demo = NotchDemo()

    public init() {}

    var deadline: Date? { demo.deadline }

    /// What the demo draws on every notch while it runs, ahead of what's really playing: it never starts with something
    /// playing and ends when something does. `nil` when it isn't running.
    var notchState: NotchState? {
        switch demo.step {
        case .resting: .resting
        case .expanded: .expanded
        case .hint: .hint
        case nil: nil
        }
    }

    /// The card the demo opens, or `nil` when it leaves the card to the notch.
    var card: NotchCard? { demo.step == .expanded ? .player : nil }

    /// When the preview track started while the demo shows one, which its position runs on from; the app draws the track.
    var trackStart: Date? { demo.showsTrack ? demo.startedAt : nil }

    /// A touch or something playing ends the demo at once, before the action meets the notch it drew over. The welcome
    /// window opens when the demo ends, and so asks for `.showWelcome`.
    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        let opens: Bool
        switch action {
        case .launched(let firstRun):
            opens = launched(firstRun: firstRun, isPlaying: shared.playback?.isPlaying == true, at: now)
        case .welcomeClosed:
            welcomeClosed()
            opens = false
        case .tick:
            opens = advance(to: now)
        default:
            opens = Self.endsDemo(action) && endDemo()
        }
        return opens ? [.showWelcome] : []
    }

    /// Whether `action` is the user touching a notch or something starting to play.
    private static func endsDemo(_ action: AppAction) -> Bool {
        switch action {
        case .pointer(_, let inside): inside
        case .hover, .menu: true
        case .playbackReported(let playback): playback?.isPlaying == true
        default: false
        }
    }

    /// Handles the launch. On a first launch, and only the first time this is called, the demo starts and the welcome
    /// window waits for it, unless something is already playing, which leaves no demo to show. Returns whether the
    /// welcome window should open now.
    mutating func launched(firstRun: Bool, isPlaying: Bool, at date: Date) -> Bool {
        guard firstRun, welcome == .notShown else { return false }
        welcome = .waiting
        guard !isPlaying else { return demoEnded() }
        demo.start(at: date)
        return false
    }

    /// Moves the demo on. Returns whether the welcome window should open now.
    mutating func advance(to date: Date) -> Bool {
        demo.advance(to: date) && demoEnded()
    }

    /// Ends the demo at once. Returns whether the welcome window should open now.
    mutating func endDemo() -> Bool {
        guard demo.isRunning else { return false }
        demo.end()
        return demoEnded()
    }

    mutating func welcomeClosed() {
        welcome = .closed
    }

    private mutating func demoEnded() -> Bool {
        guard welcome == .waiting else { return false }
        welcome = .showing
        return true
    }
}
