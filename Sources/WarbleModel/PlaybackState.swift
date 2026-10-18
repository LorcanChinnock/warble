import Foundation

/// What's playing, whichever app or source reports it.
public struct PlaybackState: Equatable, Sendable {
    /// The app that's playing, such as `com.apple.Music`. For a tab, the browser.
    public var bundleIdentifier: String
    public var title: String
    public var artist: String?
    public var album: String?
    /// `nil` for a live stream, which has no end.
    public var duration: TimeInterval?
    /// The position the source last reported, at `elapsedTimestamp`.
    public var elapsed: TimeInterval
    public var elapsedTimestamp: Date
    /// 1 at normal speed, 2 at double speed, 0 while paused.
    public var rate: Double
    /// The image's encoded bytes, PNG or JPEG.
    public var artwork: Data?
    /// `nil` when the source doesn't say.
    public var shuffle: ShuffleMode?
    public var repeatMode: RepeatMode?

    public init(
        bundleIdentifier: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval = 0,
        elapsedTimestamp: Date,
        rate: Double = 0,
        artwork: Data? = nil,
        shuffle: ShuffleMode? = nil,
        repeatMode: RepeatMode? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedTimestamp = elapsedTimestamp
        self.rate = rate
        self.artwork = artwork
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }

    public var isPlaying: Bool { rate != 0 }

    /// The position at `date`, run on from the last report at `rate`, so the progress bar needs no polling. It stays
    /// within the track: a source can report late, and the next track's report can lag the end of this one.
    public func elapsed(at date: Date) -> TimeInterval {
        clamped(elapsed + rate * date.timeIntervalSince(elapsedTimestamp))
    }

    /// This state after a seek to `position` at `date`, so the progress bar moves before the source reports back.
    public func seeked(to position: TimeInterval, at date: Date) -> PlaybackState {
        var state = self
        state.elapsed = clamped(position)
        state.elapsedTimestamp = date
        return state
    }

    private func clamped(_ position: TimeInterval) -> TimeInterval {
        min(max(position, 0), duration ?? .infinity)
    }
}

public enum ShuffleMode: String, CaseIterable, Sendable {
    case off, albums, songs
}

public enum RepeatMode: String, CaseIterable, Sendable {
    case off, one, all
}
