import Foundation

/// Synced lyrics for the track playing, and the line a resting notch shows under it. It's off until Settings turns it
/// on, and then asks for a track's lyrics once, when the track first plays. Like `HoverIntent` it holds no timer: while a
/// line shows, `deadline` is when the next starts, and `update(for:at:)` moves it on.
public struct LyricsState: Equatable, Sendable {
    /// How far ahead of the position a line is looked up, more than rounding leaves between a deadline and the position
    /// worked out at it and less than anyone could see, so the line due at a deadline is the one that shows.
    static let tolerance: TimeInterval = 0.01

    /// Whether Settings turned lyrics on.
    public internal(set) var isOn: Bool
    /// The track the last fetch was for, which `lyrics` belong to.
    public internal(set) var query: LyricsQuery?
    /// The lyrics found for `query`, or `nil` while they load or when there are none.
    public internal(set) var lyrics: Lyrics?
    /// The line showing now, or `nil` while paused, Idle, before the first line or with no lyrics.
    public internal(set) var line: Lyrics.Line?
    /// The lines around the position, for the lyrics card, or `nil` with no lyrics for what's shown. Unlike `line` it
    /// stays while paused.
    public internal(set) var excerpt: LyricsExcerpt?
    /// When the next line starts, or `nil` when no line is due.
    public internal(set) var deadline: Date?
    /// Bumped by every fetch and by turning lyrics off, so an answer that arrives after a later one has begun is dropped.
    public internal(set) var fetches = 0

    public init(isOn: Bool = false) {
        self.isOn = isOn
    }

    /// Whether a resting notch draws the strip: a line with words is showing, not a gap such as an instrumental break.
    public var showsLine: Bool {
        line.map { !$0.text.isEmpty } ?? false
    }

    /// The query to look up for `playback`, or `nil` when lyrics are off or it's no song: nothing, speech, or a source
    /// that reports no length, such as a live stream. An episode or a chapter has no lyrics, so its title isn't sent.
    func query(for playback: PlaybackState?) -> LyricsQuery? {
        guard isOn, let playback, !SpokenWord.contains(playback),
              let query = LyricsQuery(playback), query.duration != nil
        else { return nil }
        return query
    }

    /// Turns lyrics on or off. Off forgets them and drops any answer still on its way.
    mutating func turn(on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if !on {
            query = nil
            lyrics = nil
            fetches += 1
        }
    }

    /// Takes the answer to the fetch numbered `pass`, unless another has begun since.
    mutating func loaded(_ lyrics: Lyrics?, pass: Int) {
        guard pass == fetches, query != nil else { return }
        self.lyrics = lyrics
    }

    /// Brings the line up to date for `playback`, what the notch shows, at `now`, and returns the fetch to ask for when
    /// it's a track whose lyrics haven't been asked for. Only a track that plays is looked up, so a pause, a seek or new
    /// art never asks again, and nothing is asked for a track that's only been paused.
    mutating func update(for playback: PlaybackState?, at now: Date) -> AppEffect? {
        let wanted = query(for: playback)
        var fetch: AppEffect?
        if let wanted, wanted != query, playback?.isPlaying == true {
            query = wanted
            lyrics = nil
            fetches += 1
            fetch = .fetchLyrics(wanted, pass: fetches)
        }
        let shown = wanted == query ? lyrics : nil
        (line, deadline) = Self.line(in: shown, for: playback, at: now)
        excerpt = shown.flatMap { lyrics in playback.flatMap { LyricsExcerpt(lyrics, at: $0.elapsed(at: now) + Self.tolerance) } }
        return fetch
    }

    /// The line showing in `lyrics` while `playback` plays at `now`, and when the next starts. Nothing shows while
    /// paused or played backwards, and no line is due after the track ends.
    static func line(in lyrics: Lyrics?, for playback: PlaybackState?, at now: Date) -> (Lyrics.Line?, Date?) {
        guard let lyrics, let playback, playback.rate > 0, playback.rate.isFinite else { return (nil, nil) }
        let position = playback.elapsed(at: now) + tolerance
        let line = lyrics.line(at: position)
        guard let next = lyrics.nextChange(after: position), next <= playback.duration ?? .infinity else { return (line, nil) }
        // From the report rather than from now, so every update while the same line shows gives the same deadline.
        let due = playback.elapsedTimestamp + (next - playback.elapsed) / playback.rate
        return (line, due > now ? due : nil)
    }
}
