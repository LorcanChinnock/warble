import Foundation

/// Follows the output of mediaremote-adapter's `stream --micros` command, one JSON object per line, and keeps what's
/// playing. A line either replaces everything known (`diff` false) or changes only the keys it has, where `null`
/// removes a key. Artwork usually comes a line after the title, and a pause or seek comes as two lines: `playing` first,
/// then the new position.
public struct AdapterStream: Sendable {
    public private(set) var state: PlaybackState?
    private var payload: [String: AdapterValue] = [:]
    /// The base64 text the artwork was decoded from, so a line that changes something else doesn't decode it again.
    private var artworkText: String?
    private var artwork: Data?

    public init() {}

    /// Applies one line received at `date`, and returns whether `state` changed. Lines of another type change nothing.
    @discardableResult
    public mutating func apply(_ line: Data, at date: Date) throws -> Bool {
        let message = try JSONDecoder().decode(Message.self, from: line)
        guard message.type == "data" else { return false }
        if message.diff {
            for (key, value) in message.payload {
                payload[key] = value == .null ? nil : value
            }
        } else {
            payload = message.payload.filter { $0.value != .null }
        }
        if case .string(let text) = payload[Key.artworkData] {
            if text != artworkText {
                artworkText = text
                artwork = Data(base64Encoded: text)
            }
        } else {
            artworkText = nil
            artwork = nil
        }
        if !payload.isEmpty {
            holdPosition(at: date)
        }
        let previous = state
        state = PlaybackState(adapterPayload: payload, artwork: artwork)
        return state != previous
    }

    /// Pins the position to `date` when the adapter hasn't: with no timestamp yet, and when playback starts or stops on
    /// a line before the one with the new position, which would otherwise jump back to where it was last reported.
    /// It goes into the payload, so later lines that change something else keep it.
    private mutating func holdPosition(at date: Date) {
        guard payload[Key.timestampEpochMicros] != nil else {
            payload[Key.timestampEpochMicros] = .number(date.timeIntervalSince1970 * 1_000_000)
            return
        }
        guard let state, let next = PlaybackState(adapterPayload: payload, artwork: nil),
              next.bundleIdentifier == state.bundleIdentifier, next.title == state.title,
              next.rate != state.rate, next.elapsedTimestamp == state.elapsedTimestamp else { return }
        payload[Key.elapsedTimeMicros] = .number(state.elapsed(at: date) * 1_000_000)
        payload[Key.timestampEpochMicros] = .number(date.timeIntervalSince1970 * 1_000_000)
    }

    private struct Message: Decodable {
        let type: String
        let diff: Bool
        let payload: [String: AdapterValue]
    }
}

/// One value in the adapter's payload. Every key holds a string, a number, a Boolean or `null`.
enum AdapterValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }
}

/// The payload keys Warble reads, as `stream --micros` names them.
enum Key {
    static let bundleIdentifier = "bundleIdentifier"
    static let parentApplicationBundleIdentifier = "parentApplicationBundleIdentifier"
    static let title = "title"
    static let artist = "artist"
    static let album = "album"
    static let playing = "playing"
    static let playbackRate = "playbackRate"
    static let durationMicros = "durationMicros"
    static let elapsedTimeMicros = "elapsedTimeMicros"
    static let timestampEpochMicros = "timestampEpochMicros"
    static let artworkData = "artworkData"
    static let shuffleMode = "shuffleMode"
    static let repeatMode = "repeatMode"
    static let mediaType = "mediaType"
}

extension PlaybackState {
    /// What a merged adapter payload says is playing, or `nil` when it has no title or app.
    init?(adapterPayload payload: [String: AdapterValue], artwork: Data?) {
        // A tab in Safari reports WebKit's GPU process, with Safari as its parent.
        guard let app = payload[Key.parentApplicationBundleIdentifier]?.string ?? payload[Key.bundleIdentifier]?.string,
              !app.isEmpty,
              let title = payload[Key.title]?.string, !title.isEmpty else { return nil }
        func text(_ key: String) -> String? {
            payload[key]?.string.flatMap { $0.isEmpty ? nil : $0 }
        }
        func seconds(_ key: String) -> TimeInterval? {
            payload[key]?.number.map { $0 / 1_000_000 }
        }
        let playing = payload[Key.playing]?.bool ?? false
        let rate = payload[Key.playbackRate]?.number ?? 1
        self.init(
            bundleIdentifier: app,
            title: title,
            artist: text(Key.artist),
            album: text(Key.album),
            duration: seconds(Key.durationMicros).flatMap { $0 > 0 ? $0 : nil },
            elapsed: seconds(Key.elapsedTimeMicros) ?? 0,
            elapsedTimestamp: Date(timeIntervalSince1970: seconds(Key.timestampEpochMicros) ?? 0),
            // `playing` changes on the line before `playbackRate` does, so it decides; the rate only gives the speed.
            rate: playing ? (rate > 0 ? rate : 1) : 0,
            artwork: artwork,
            shuffle: payload[Key.shuffleMode]?.number.flatMap(ShuffleMode.init(adapterValue:)),
            repeatMode: payload[Key.repeatMode]?.number.flatMap(RepeatMode.init(adapterValue:)),
            mediaType: payload[Key.mediaType]?.string.map(MediaType.init(adapterValue:))
        )
    }
}

extension MediaType {
    /// MediaRemote's name for it, such as `MRMediaRemoteMediaTypePodcast`. The adapter passes on whatever the app set,
    /// which isn't documented, so only the end of the name counts.
    init(adapterValue: String) {
        let name = adapterValue.lowercased()
        self = if name.hasSuffix("podcast") {
            .podcast
        } else if name.hasSuffix("audiobook") {
            .audiobook
        } else if name.hasSuffix("music") {
            .music
        } else {
            .other
        }
    }
}

// MediaRemote numbers each mode from 1, and the adapter's `shuffle` and `repeat` commands take the same numbers.
extension ShuffleMode {
    init?(adapterValue: Double) {
        switch adapterValue {
        case 1: self = .off
        case 2: self = .albums
        case 3: self = .songs
        default: return nil
        }
    }

    var adapterValue: Int {
        switch self {
        case .off: 1
        case .albums: 2
        case .songs: 3
        }
    }
}

extension RepeatMode {
    init?(adapterValue: Double) {
        switch adapterValue {
        case 1: self = .off
        case 2: self = .one
        case 3: self = .all
        default: return nil
        }
    }

    var adapterValue: Int {
        switch self {
        case .off: 1
        case .one: 2
        case .all: 3
        }
    }
}

extension PlaybackCommand {
    /// The adapter command that does this, as the arguments that follow the script, framework and test client.
    public var adapterArguments: [String] {
        switch self {
        case .play: ["send", "0"]
        case .pause: ["send", "1"]
        case .togglePlayPause: ["send", "2"]
        case .nextTrack: ["send", "4"]
        case .previousTrack: ["send", "5"]
        case .seek(let position): ["seek", String(Int64((max(position, 0) * 1_000_000).rounded()))]
        case .setShuffle(let mode): ["shuffle", String(mode.adapterValue)]
        case .setRepeat(let mode): ["repeat", String(mode.adapterValue)]
        }
    }
}
