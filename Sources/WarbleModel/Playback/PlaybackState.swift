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
    /// A link to the track that opens anywhere, such as Spotify's, where the source gives one.
    public var link: URL?
    /// What kind of thing is playing, or `nil` when the source doesn't say.
    public var mediaType: MediaType?

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
        repeatMode: RepeatMode? = nil,
        link: URL? = nil,
        mediaType: MediaType? = nil
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
        self.link = link
        self.mediaType = mediaType
    }

    public var isPlaying: Bool { rate != 0 }

    /// How a position in a track reads: "3:07", or "1:02:03" past an hour.
    public static func positionLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        let twoDigits = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(twoDigits(minutes)):\(twoDigits(rest))" : "\(minutes):\(twoDigits(rest))"
    }

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

    /// This state playing or paused from `date`, kept where it had got to, so play/pause shows at once rather than when
    /// the source reports back. Playing again runs at normal speed.
    public func playing(_ isPlaying: Bool, at date: Date) -> PlaybackState {
        guard isPlaying != self.isPlaying else { return self }
        var state = seeked(to: elapsed(at: date), at: date)
        state.rate = isPlaying ? 1 : 0
        return state
    }

    /// The position `seconds` on from where it is at `date`, or back for a negative number, kept within the track.
    public func position(skipping seconds: TimeInterval, at date: Date) -> TimeInterval {
        clamped(elapsed(at: date) + seconds)
    }

    private func clamped(_ position: TimeInterval) -> TimeInterval {
        min(max(position, 0), duration ?? .infinity)
    }
}

/// What kind of thing a source says is playing.
public enum MediaType: Equatable, Sendable {
    case music, podcast, audiobook
    /// Anything else, such as a video or a page's audio.
    case other
}

public enum ShuffleMode: String, CaseIterable, Sendable {
    case off, albums, songs

    /// What the shuffle button turns it to: on shuffles songs, and any shuffle turns off.
    public var next: ShuffleMode {
        self == .off ? .songs : .off
    }
}

public enum RepeatMode: String, CaseIterable, Sendable {
    case off, one, all

    /// What the repeat button turns it to, in Music's order: off, all, one, then off again.
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
