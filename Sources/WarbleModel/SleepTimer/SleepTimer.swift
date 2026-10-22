import Foundation

/// A sleep timer that is running: pause what's playing after a set time, or at the end of the track. It holds no timers:
/// `deadline` is when it's due, and `AppState.deadline` includes it, so `Store` still arms one timer at most.
public struct SleepTimer: Equatable, Sendable {
    /// What the listener can ask for.
    public enum Choice: Equatable, Sendable, CaseIterable {
        case fifteenMinutes
        case thirtyMinutes
        case oneHour
        case endOfTrack

        /// How long a fixed timer runs, or `nil` for the end of the track.
        public var duration: TimeInterval? {
            switch self {
            case .fifteenMinutes: 15 * 60
            case .thirtyMinutes: 30 * 60
            case .oneHour: 60 * 60
            case .endOfTrack: nil
            }
        }
    }

    /// Whether the timer is due yet.
    public enum Status: Equatable, Sendable {
        case waiting
        case due
    }

    public let choice: Choice
    /// When the playing app is paused if nothing changes. A fixed timer's is set when it starts; the end of the track's
    /// is worked out again from each report and seek.
    public private(set) var deadline: Date

    /// The track an End of track timer was set on; a different one reported before its end counts as the end.
    private let track: Track

    /// Starts `choice` on `playback` at `now`, or returns `nil` for End of track on a track with no length, such as a
    /// live stream.
    public init?(_ choice: Choice, playback: PlaybackState, at now: Date) {
        self.choice = choice
        track = Track(playback)
        if let duration = choice.duration {
            deadline = now + duration
        } else if let end = Self.end(of: playback, at: now) {
            deadline = end
        } else {
            return nil
        }
    }

    /// Brings the timer up to date with `playback` at `now`, and says whether it's due.
    public mutating func follow(_ playback: PlaybackState, at now: Date) -> Status {
        if choice == .endOfTrack {
            guard Track(playback) == track else { return .due }
            if let end = Self.end(of: playback, at: now) {
                deadline = end
            }
        }
        return deadline <= now ? .due : .waiting
    }

    /// When `playback` ends if it plays on at its rate, or `nil` with no length or while paused.
    private static func end(of playback: PlaybackState, at now: Date) -> Date? {
        guard let duration = playback.duration, playback.rate > 0 else { return nil }
        return now + (duration - playback.elapsed(at: now)) / playback.rate
    }

    /// What tells one track from the next; the position and rate don't.
    private struct Track: Equatable, Sendable {
        var bundleIdentifier: String
        var title: String
        var artist: String?
        var album: String?
        var duration: TimeInterval?

        init(_ state: PlaybackState) {
            bundleIdentifier = state.bundleIdentifier
            title = state.title
            artist = state.artist
            album = state.album
            duration = state.duration
        }
    }
}
