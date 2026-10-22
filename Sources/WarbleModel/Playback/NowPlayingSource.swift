import Foundation

/// What Warble can ask a player to do.
public enum PlaybackCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    /// To a position in seconds from the start.
    case seek(to: TimeInterval)
    case setShuffle(ShuffleMode)
    case setRepeat(RepeatMode)
}

/// Where Warble learns what's playing and sends commands. Everything that touches MediaRemote or a player's scripting
/// stays behind this, so a change in macOS means replacing one implementation.
public protocol NowPlayingSource: Sendable {
    /// The current state, then each change to it; `nil` when nothing is playing. Warble reads it once.
    var states: AsyncStream<PlaybackState?> { get }

    func send(_ command: PlaybackCommand) async
}
