import Foundation

/// The last track played, which the idle card shows. It outlasts what's playing, and Warble too: it's read from disk at
/// launch and saved whenever a new track or new art arrives.
public struct LastPlayedState: Feature {
    public internal(set) var lastPlayed: LastPlayed?
    /// The state last remembered, so a pause or a seek doesn't remember it again.
    public internal(set) var remembered: PlaybackState?
    /// Bumped by every track remembered, so one whose art finishes shrinking after the next has begun is dropped.
    public internal(set) var remembers = 0

    public init() {}

    var deadline: Date? { nil }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .lastPlayedLoaded(let saved):
            // A track that played since Warble opened is newer than the one saved.
            if remembered == nil, let saved {
                lastPlayed = saved
            }
        case .remembered(let latest, let pass):
            guard pass == remembers else { break }
            lastPlayed = latest
            return [.saveLastPlayed(latest)]
        default:
            break
        }
        return []
    }

    /// Keeps what's playing as the last track played, with a small copy of its art, and saves it for the next launch. Only
    /// a new track or new art does any work.
    mutating func follow(_ shared: SharedState, at now: Date) -> [AppEffect] {
        guard let playback = shared.playback, LastPlayed.changes(from: remembered, to: playback) else { return [] }
        remembered = playback
        remembers += 1
        return [.remember(playback, pass: remembers)]
    }
}
