import Foundation

/// What `warble now` prints: what's playing, as one value with fixed JSON keys, for status bars such as sketchybar and
/// tmux. Built from `AppState`, so it says what the notch says.
///
/// The keys are `status` (`playing`, `paused` or `stopped`), then, when there's a track, `title`, `artist`, `album`,
/// `app` (the player's bundle identifier), `position` and `duration` in whole seconds, `shuffle` (`off`, `albums` or
/// `songs`) and `repeat` (`off`, `one` or `all`), and `volume` from 0 to 100 when the output has one. A key with
/// nothing to say is left out.
public struct NowPlayingSnapshot: Equatable, Sendable, Codable {
    public enum Status: String, Codable, Sendable {
        case playing, paused, stopped
    }

    public var status: Status
    public var title: String?
    public var artist: String?
    public var album: String?
    public var app: String?
    public var position: Int?
    public var duration: Int?
    public var shuffle: String?
    public var repeatMode: String?
    public var volume: Int?

    private enum CodingKeys: String, CodingKey {
        case status, title, artist, album, app, position, duration, shuffle, volume
        case repeatMode = "repeat"
    }

    /// `volume` is the output's, from 0 to 1, read when the command came in, or `nil` when it can't be changed.
    public init(_ state: AppState, volume: Double?, at now: Date) {
        self.volume = volume.map { Int(($0 * 100).rounded()) }
        guard let playback = state.playback else {
            status = .stopped
            return
        }
        status = playback.isPlaying ? .playing : .paused
        title = playback.title
        artist = playback.artist
        album = playback.album
        app = playback.bundleIdentifier
        position = Int(playback.elapsed(at: now).rounded(.down))
        duration = playback.duration.map { Int($0.rounded()) }
        shuffle = playback.shuffle?.rawValue
        repeatMode = playback.repeatMode?.rawValue
    }

    /// The snapshot as one line of JSON with its keys in order, so the same state always prints the same.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // A struct of strings and numbers always encodes.
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// The snapshot as a few lines for a person: `Playing: Song by Artist`, then what else is known.
    public var text: String {
        guard status != .stopped, let title else {
            return (["Nothing is playing."] + volumeLine).joined(separator: "\n")
        }
        var lines = ["\(status == .playing ? "Playing" : "Paused"): " + (artist.map { "\(title) by \($0)" } ?? title)]
        if let album {
            lines.append("Album: \(album)")
        }
        if let position {
            let label = PlaybackState.positionLabel(TimeInterval(position))
            lines.append("Position: " + (duration.map { "\(label) of \(PlaybackState.positionLabel(TimeInterval($0)))" } ?? label))
        }
        if let app {
            lines.append("App: \(app)")
        }
        return (lines + volumeLine).joined(separator: "\n")
    }

    private var volumeLine: [String] {
        volume.map { ["Volume: \($0)%"] } ?? []
    }
}
