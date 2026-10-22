import Foundation

/// What a first launch shows: the notch demo, then the welcome window, each once, then left alone for good.
public struct Onboarding: Equatable, Sendable {
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
