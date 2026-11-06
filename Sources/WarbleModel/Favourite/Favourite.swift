import Foundation

/// The heart on the open card, which adds the song Music is playing to the listener's Favourites or takes it out. It's
/// off until Settings turns it on, and only Music has it: no other player lets Warble read or set a like
/// (docs/spikes/likes.md). It reads Music's `favorited` once each time the card opens on a track, with no timer, and a
/// click shows the change at once and sets it, as a play/pause click does. A track whose `favorited` can't be read or set
/// has no heart.
public struct Favourite: Feature {
    /// The only player with a heart.
    public static let music = "com.apple.Music"

    /// A track as far as its heart goes: the same track whatever its position or play state.
    public struct Track: Equatable, Sendable {
        public var title: String
        public var artist: String?
        public var album: String?

        public init(title: String, artist: String? = nil, album: String? = nil) {
            self.title = title
            self.artist = artist
            self.album = album
        }

        /// The track `playback` shows, when Music is playing one with a title.
        init?(_ playback: PlaybackState?) {
            guard let playback, playback.bundleIdentifier == Favourite.music, !playback.title.isEmpty else { return nil }
            self.init(title: playback.title, artist: playback.artist, album: playback.album)
        }
    }

    /// One read or set of `favorited`, numbered so an answer that a later question overtook is dropped.
    public struct Ask: Equatable, Sendable {
        public var track: Track
        public var number: Int

        public init(track: Track, number: Int) {
            self.track = track
            self.number = number
        }
    }

    /// Whether Settings has turned the heart on. It starts off.
    public internal(set) var isEnabled = false
    /// The track `isFavourited` is about, or `nil` before the first answer.
    var track: Track?
    /// Whether `track` is a favourite, or `nil` when Music couldn't say, which hides the heart.
    var isFavourited: Bool?
    /// The track read since the card opened, so it's read once per opening, and again only when the track changes.
    var readWhileOpen: Track?
    /// How many questions have gone to Music; only the answer to the last one counts.
    var asked = 0

    public init() {}

    /// The heart has no timer.
    var deadline: Date? { nil }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .favouriteHeartChanged(let on):
            // The count of questions goes on, so an answer still on its way from before is never taken for a new one.
            isEnabled = on
            track = nil
            isFavourited = nil
            readWhileOpen = nil
        case .favouriteAnswered(let value, let ask):
            guard isEnabled, ask.number == asked, ask.track == Track(shared.playback) else { return [] }
            track = ask.track
            isFavourited = value
        case .toggleFavourite:
            guard isEnabled, let current = Track(shared.playback), current == track, let favourited = isFavourited else { return [] }
            // Shown at once; the answer, what Music has after the set, replaces it, and a read still on its way is dropped.
            isFavourited = !favourited
            asked += 1
            return [.setFavourite(!favourited, Ask(track: current, number: asked))]
        default:
            break
        }
        return []
    }

    /// Reads `favorited` when the player's card opens on a Music track, or the track changes while it's open, and asks
    /// nothing while it's closed. `cardOpen` is whether any notch shows the player's card.
    mutating func follow(_ shared: SharedState, cardOpen: Bool) -> [AppEffect] {
        guard isEnabled, cardOpen, shared.showsPlayback, let current = Track(shared.playback) else {
            if !cardOpen { readWhileOpen = nil }
            return []
        }
        guard readWhileOpen != current else { return [] }
        readWhileOpen = current
        asked += 1
        return [.readFavourite(Ask(track: current, number: asked))]
    }

    /// Whether the heart over `shared.playback` is filled, or `nil` when there's no heart: it's off, another player is
    /// playing, or Music hasn't answered for this track or couldn't.
    func shown(_ shared: SharedState) -> Bool? {
        guard isEnabled, let current = Track(shared.playback), current == track else { return nil }
        return isFavourited
    }
}

extension Favourite {
    /// Returns whether the track titled `title` is a favourite, and fails when Music plays nothing, plays another track or
    /// can't say, such as for a track `favorited` doesn't apply to. `loved`, which it replaced, fails on every track.
    public static func readScript(title: String) -> String {
        tellMusic(about: title, "return favorited of current track")
    }

    /// Makes the track titled `title` a favourite or not, and returns what it is afterwards. It fails when Music plays
    /// another track by then, so a click never changes a track the card wasn't showing.
    public static func setScript(_ favourited: Bool, title: String) -> String {
        tellMusic(about: title, """
        set favorited of current track to \(favourited)
        return favorited of current track
        """)
    }

    /// `body` sent to Music, by bundle ID, once it has checked the current track is the one titled `title`, giving up
    /// after 5 seconds rather than the default 2 minutes when Music hangs.
    private static func tellMusic(about title: String, _ body: String) -> String {
        let quoted = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        with timeout of 5 seconds
            tell application id "\(music)"
                if player state is stopped then error "Nothing is playing" number -1728
                if name of current track is not "\(quoted)" then error "Another track is playing" number -1728
                \(body.replacingOccurrences(of: "\n", with: "\n        "))
            end tell
        end timeout
        """
    }
}
