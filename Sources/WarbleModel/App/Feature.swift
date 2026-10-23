import Foundation

/// A slice of `AppState` that decides its own part, so a feature edits its own folder and `reduce` only routes to it.
/// Like `reduce` it's pure: no clock, no timers and no I/O.
protocol Feature: Equatable, Sendable {
    /// Handles the actions that are about this feature alone; any other it ignores.
    mutating func reduce(_ action: AppAction, at now: Date) -> [AppEffect]

    /// Follows what the notches show once the action and the settle pass are done, so a track that is no longer shown has
    /// nothing to follow. `playback` is `nil` while nothing shows.
    mutating func follow(_ playback: PlaybackState?, at now: Date) -> [AppEffect]

    /// When the feature next changes without an action, or `nil`. It joins `AppState.deadline`.
    var deadline: Date? { get }
}
