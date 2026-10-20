import Foundation

/// A player Warble reads and controls with AppleScript when mediaremote-adapter can't run, such as after a macOS update
/// breaks it. Only Music and Spotify, the two most common, and each is scripted only while it's running, since a script
/// that names an app opens it.
public enum ScriptedPlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    public var bundleIdentifier: String { rawValue }

    /// The distributed notification the player posts when it plays, pauses or changes track. It doesn't post one for a
    /// seek, so Warble reads the player again after each command it sends.
    public var changeNotification: String {
        switch self {
        case .music: "com.apple.Music.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        }
    }

    /// Returns `{"stopped"}` when nothing is loaded, otherwise the list that `PlaybackState(player:report:at:)` reads:
    /// state, title, artist, album, duration and position in seconds, shuffle, repeat, and Spotify's artwork URL.
    public var stateScript: String {
        switch self {
        case .music:
            tell("""
            if player state is stopped then return {"stopped"}
            set theTrack to current track
            set playState to "paused"
            if player state is playing then set playState to "playing"
            set trackDuration to missing value
            try
                set trackDuration to duration of theTrack
            end try
            set shuffleMode to "off"
            if shuffle enabled then
                set shuffleMode to "songs"
                if shuffle mode is not songs then set shuffleMode to "albums"
            end if
            set repeatMode to "off"
            if song repeat is one then set repeatMode to "one"
            if song repeat is all then set repeatMode to "all"
            return {playState, name of theTrack, artist of theTrack, album of theTrack, trackDuration, player position, shuffleMode, repeatMode, missing value}
            """)
        case .spotify:
            tell("""
            if player state is stopped then return {"stopped"}
            set theTrack to current track
            set playState to "paused"
            if player state is playing then set playState to "playing"
            set shuffleMode to "off"
            if shuffling then set shuffleMode to "songs"
            set repeatMode to "off"
            if repeating then set repeatMode to "all"
            return {playState, name of theTrack, artist of theTrack, album of theTrack, (duration of theTrack) / 1000, player position, shuffleMode, repeatMode, artwork url of theTrack}
            """)
        }
    }

    /// Returns the current track's artwork as its encoded bytes, for a player whose `stateScript` can't give a URL, or
    /// `missing value` for a track without any, such as an imported file, rather than failing.
    public var artworkScript: String? {
        switch self {
        case .music: tell("""
            if (count of artworks of current track) is 0 then return missing value
            return raw data of artwork 1 of current track
            """)
        case .spotify: nil
        }
    }

    /// Spotify's scripting has only on and off for shuffle and repeat, so any shuffle turns it on. Repeat reads back as
    /// all, so repeating one, the step after all on the repeat button, turns it off; otherwise the button could never
    /// turn it off.
    public func script(for command: PlaybackCommand) -> String {
        switch command {
        case .play: tell("play")
        case .pause: tell("pause")
        case .togglePlayPause: tell("playpause")
        case .nextTrack: tell("next track")
        case .previousTrack: tell("previous track")
        case .seek(let position): tell("set player position to \(max(position, 0))")
        case .setShuffle(let mode):
            switch (self, mode) {
            case (.music, .off): tell("set shuffle enabled to false")
            case (.music, .songs): tell("set shuffle mode to songs\nset shuffle enabled to true")
            case (.music, .albums): tell("set shuffle mode to albums\nset shuffle enabled to true")
            case (.spotify, _): tell("set shuffling to \(mode != .off)")
            }
        case .setRepeat(let mode):
            switch self {
            case .music: tell("set song repeat to \(mode.rawValue)")
            case .spotify: tell("set repeating to \(mode == .all)")
            }
        }
    }

    /// `body` sent to this player, by bundle ID so a renamed app still answers, giving up after 5 seconds rather than
    /// the default 2 minutes when the player hangs.
    private func tell(_ body: String) -> String {
        """
        with timeout of 5 seconds
            tell application id "\(bundleIdentifier)"
                \(body.replacingOccurrences(of: "\n", with: "\n        "))
            end tell
        end timeout
        """
    }
}

/// One item of a script's result.
public enum ScriptValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case missing

    var text: String? {
        if case .text(let value) = self { value } else { nil }
    }

    var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }
}

extension PlaybackState {
    /// What `player`'s `stateScript` reported at `date`, or `nil` when it's stopped, has no title or isn't a list Warble
    /// knows.
    public init?(player: ScriptedPlayer, report: [ScriptValue], at date: Date) {
        guard report.count == 9, let state = report[0].text, state != "stopped",
              let title = report[1].text, !title.isEmpty else { return nil }
        func text(_ index: Int) -> String? {
            report[index].text.flatMap { $0.isEmpty ? nil : $0 }
        }
        self.init(
            bundleIdentifier: player.bundleIdentifier,
            title: title,
            artist: text(2),
            album: text(3),
            // A radio stream in Music has no duration, and reports 0 in Spotify.
            duration: report[4].number.flatMap { $0 > 0 ? $0 : nil },
            elapsed: report[5].number ?? 0,
            elapsedTimestamp: date,
            rate: state == "playing" ? 1 : 0,
            shuffle: text(6).flatMap(ShuffleMode.init(rawValue:)),
            repeatMode: text(7).flatMap(RepeatMode.init(rawValue:))
        )
    }

    /// The artwork URL in a `stateScript` report, which only Spotify gives.
    public static func artworkURL(in report: [ScriptValue]) -> URL? {
        guard report.count == 9 else { return nil }
        return report[8].text.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// Whether `other` is the same track, so its artwork is the same.
    public func isSameTrack(as other: PlaybackState?) -> Bool {
        guard let other else { return false }
        return bundleIdentifier == other.bundleIdentifier && title == other.title && artist == other.artist
            && album == other.album
    }
}

/// Which scripted player to show when both are running. A playing player comes before a paused one, and otherwise the
/// one that changed last, which is usually the one the user just used.
public struct ScriptedNowPlaying: Equatable, Sendable {
    private var states: [ScriptedPlayer: PlaybackState] = [:]
    /// The players with a state, the one that changed last at the end.
    private var order: [ScriptedPlayer] = []

    public init() {}

    public var current: PlaybackState? {
        let players = order.reversed()
        let shown = players.first { states[$0]?.isPlaying == true } ?? players.first
        return shown.flatMap { states[$0] }
    }

    public func state(of player: ScriptedPlayer) -> PlaybackState? {
        states[player]
    }

    /// Records what `player` reports, `nil` when it stopped or quit.
    public mutating func update(_ player: ScriptedPlayer, _ state: PlaybackState?) {
        guard states[player] != state else { return }
        order.removeAll { $0 == player }
        states[player] = state
        if state != nil {
            order.append(player)
        }
    }
}
