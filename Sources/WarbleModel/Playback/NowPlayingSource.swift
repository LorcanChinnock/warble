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

    /// What each app reports, by bundle identifier, with `nil` once that app stops reporting. Warble reads it once.
    /// A source that can see only the one player macOS picks needn't provide it: the default turns `states` into reports,
    /// ending the earlier app's whenever another takes over.
    var reports: AsyncStream<SourceReport> { get }

    func send(_ command: PlaybackCommand) async
}

/// One app's playback, or `nil` when it stopped reporting, such as when it quit or the tab closed.
public struct SourceReport: Equatable, Sendable {
    public var bundleIdentifier: String
    public var state: PlaybackState?

    public init(bundleIdentifier: String, state: PlaybackState?) {
        self.bundleIdentifier = bundleIdentifier
        self.state = state
    }
}

extension NowPlayingSource {
    public var reports: AsyncStream<SourceReport> {
        let states = states
        return AsyncStream { continuation in
            let task = Task {
                var current: String?
                for await state in states {
                    if let current, current != state?.bundleIdentifier {
                        continuation.yield(SourceReport(bundleIdentifier: current, state: nil))
                    }
                    current = state?.bundleIdentifier
                    if let state {
                        continuation.yield(SourceReport(bundleIdentifier: state.bundleIdentifier, state: state))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
