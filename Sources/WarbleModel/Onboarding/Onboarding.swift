import Foundation

/// Where the welcome window is: asked for once on a first launch, then left alone for good.
public struct Onboarding: Equatable, Sendable {
    public enum Welcome: Equatable, Sendable {
        /// Not asked for in this launch.
        case notShown
        /// Asked for and open.
        case showing
        /// Closed, so it isn't asked for again.
        case closed
    }

    public internal(set) var welcome = Welcome.notShown

    public init() {}

    /// Handles the launch. Returns whether the welcome window should open, which it does only on a first launch and only
    /// the first time this is called.
    mutating func launched(firstRun: Bool) -> Bool {
        guard firstRun, welcome == .notShown else { return false }
        welcome = .showing
        return true
    }

    mutating func welcomeClosed() {
        welcome = .closed
    }
}
