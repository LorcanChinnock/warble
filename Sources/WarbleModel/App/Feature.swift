import Foundation

/// A slice of `AppState` that decides its own part, so a feature edits its own folder and `reduce` only routes to it.
/// Like `reduce` it's pure: no clock, no timers and no I/O.
protocol Feature: Equatable, Sendable {
    /// Handles the actions that are about this feature alone; any other it ignores.
    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect]

    /// Follows what the notches show once the action and the settle pass are done, so a track that is no longer shown has
    /// nothing to follow. A feature with nothing to follow needn't write it.
    mutating func follow(_ shared: SharedState, at now: Date) -> [AppEffect]

    /// When the feature next changes without an action, or `nil`. It joins `AppState.deadline`.
    var deadline: Date? { get }
}

extension Feature {
    mutating func follow(_ shared: SharedState, at now: Date) -> [AppEffect] { [] }
}

/// What a feature may read of the rest of `AppState`. It can't change any of it.
struct SharedState: Equatable, Sendable {
    /// What's playing as the notches show it, including a track on its way out after a report of nothing.
    var playback: PlaybackState?
    /// Whether the notches draw what's playing, which is not so while Idle.
    var showsPlayback: Bool
    /// When `playback` goes after a report of nothing, or `nil` when no hide is pending.
    var hideAt: Date?
}
