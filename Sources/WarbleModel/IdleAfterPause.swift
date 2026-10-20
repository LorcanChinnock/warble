import Foundation

/// Something playback or the pointer did.
public enum IdleEvent: Sendable {
    /// What's playing now, or `nil` once the source stops reporting.
    case playback(PlaybackState?)
    /// The pointer is over a notch, or a card is open.
    case hoverStarted
    case hoverEnded
}

/// Decides when the notch goes back to Idle after the listener pauses, so a paused track doesn't stay on screen for
/// ever. It holds no timers: after each call the owner schedules one for `deadline`, if any, and calls `advance(to:)`
/// when it fires. With nothing paused there's no deadline, so no timer runs.
public struct IdleAfterPause: Equatable, Sendable {
    /// How long a paused track stays on screen unless the user changes it in `PreferenceKey.stayVisibleAfterPausing`.
    public static let defaultDelay: TimeInterval = 10

    /// How long a paused track stays on screen once the pointer is away.
    public var delay: TimeInterval
    /// Whether the notch is Idle: nothing is playing, or a track was paused for `delay`.
    public private(set) var isIdle = true
    /// When `isIdle` turns true if nothing else happens, or `nil` when nothing is due.
    public var deadline: Date? {
        guard !isIdle, !held else { return nil }
        return countdownFrom.map { $0 + delay }
    }

    private var track: Track?
    private var playing = false
    private var held = false
    /// When the paused track's countdown started: the pause, a new track, or the pointer leaving.
    private var countdownFrom: Date?

    public init(delay: TimeInterval = Self.defaultDelay) {
        self.delay = delay
    }

    public mutating func handle(_ event: IdleEvent, at date: Date) {
        advance(to: date)
        switch event {
        case .playback(nil):
            // A source that stops reporting goes Idle at once.
            isIdle = true
            track = nil
            playing = false
            countdownFrom = nil
        case .playback(let state?):
            let current = Track(state)
            let changed = current != track || state.isPlaying != playing
            track = current
            playing = state.isPlaying
            // Reports of the same paused track, such as a seek, leave the countdown and an Idle notch alone.
            guard changed else { return }
            isIdle = false
            countdownFrom = playing ? nil : date
        case .hoverStarted:
            held = true
        case .hoverEnded:
            guard held else { return }
            held = false
            // The countdown starts again from when the pointer left.
            if countdownFrom != nil { countdownFrom = date }
        }
    }

    /// Goes Idle if the deadline is due by `date`.
    public mutating func advance(to date: Date) {
        guard let due = deadline, due <= date else { return }
        isIdle = true
        countdownFrom = nil
    }

    /// What tells one track from the next; the position and rate don't.
    private struct Track: Equatable, Sendable {
        var bundleIdentifier: String
        var title: String
        var artist: String?
        var album: String?

        init(_ state: PlaybackState) {
            bundleIdentifier = state.bundleIdentifier
            title = state.title
            artist = state.artist
            album = state.album
        }
    }
}
