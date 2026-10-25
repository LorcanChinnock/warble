import Foundation

/// The track playing now and when it started playing. It needs no timer: the time is worked out from the clock when the
/// track pauses, changes or stops.
struct ListeningSession: Equatable, Sendable {
    /// What makes two stretches of playing the same track.
    struct Track: Equatable, Sendable {
        var title: String
        var artist: String?

        /// The track being listened to in `shared`, or `nil` when nothing is: nothing plays, it's paused, or the source has
        /// reported nothing and the track is only on its way out.
        init?(_ shared: SharedState) {
            guard let playback = shared.playback, playback.isPlaying, shared.hideAt == nil else { return nil }
            title = playback.title
            artist = playback.artist
        }
    }

    var track: Track
    var since: Date

    /// The span this session made up to `now`, or `nil` when it was too short to count.
    func span(endingAt now: Date) -> ListenedSpan? {
        let seconds = now.timeIntervalSince(since)
        guard seconds >= ListenedSpan.shortest else { return nil }
        return ListenedSpan(start: since, seconds: seconds, title: track.title, artist: track.artist)
    }
}
