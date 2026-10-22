import Foundation

/// Something that happened, which `reduce` turns into a new `AppState` and any `AppEffect`s.
public enum AppAction: Equatable, Sendable {
    /// What a source reports playing, or `nil` when it reports nothing. A guess at what a command will do comes in the
    /// same way, so it shows at once and the app's next report replaces it.
    case playbackReported(PlaybackState?)
    /// The pointer came onto a notch, or a card opened (true), or both ended (false).
    case hoverChanged(Bool)
    /// Settings › General › Stay visible after pausing changed.
    case stayVisibleChanged(TimeInterval)
    /// `AppState.deadline` came due.
    case tick
}
