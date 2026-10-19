import Foundation
import Testing
@testable import WarbleModel

private let reported = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func report(
    _ state: String = "playing", title: String = "Song", artist: ScriptValue = .text("Artist"),
    duration: ScriptValue = .number(240), position: Double = 30, artworkURL: ScriptValue = .missing
) -> [ScriptValue] {
    [.text(state), .text(title), artist, .text("Album"), duration, .number(position), .text("songs"), .text("one"), artworkURL]
}

private func state(_ player: ScriptedPlayer, title: String = "Song", playing: Bool) -> PlaybackState {
    PlaybackState(bundleIdentifier: player.bundleIdentifier, title: title, elapsedTimestamp: reported, rate: playing ? 1 : 0)
}

@Test func aPlayingReportIsTheTrackAtItsPosition() throws {
    let state = try #require(PlaybackState(player: .music, report: report(), at: reported))
    #expect(state.bundleIdentifier == "com.apple.Music")
    #expect(state.title == "Song")
    #expect(state.artist == "Artist")
    #expect(state.album == "Album")
    #expect(state.duration == 240)
    #expect(state.elapsed == 30)
    #expect(state.elapsedTimestamp == reported)
    #expect(state.isPlaying)
    #expect(state.shuffle == .songs)
    #expect(state.repeatMode == .one)
}

@Test func aPausedReportHasNoRate() throws {
    let state = try #require(PlaybackState(player: .spotify, report: report("paused"), at: reported))
    #expect(state.bundleIdentifier == "com.spotify.client")
    #expect(!state.isPlaying)
    #expect(state.elapsed(at: reported + 60) == 30)
}

@Test func aStoppedPlayerShowsNothing() {
    #expect(PlaybackState(player: .music, report: [.text("stopped")], at: reported) == nil)
}

@Test func aReportWithoutATitleShowsNothing() {
    #expect(PlaybackState(player: .music, report: report(title: ""), at: reported) == nil)
}

@Test func aReportOfAnotherShapeShowsNothing() {
    #expect(PlaybackState(player: .music, report: [.text("playing"), .text("Song")], at: reported) == nil)
    #expect(PlaybackState(player: .music, report: [], at: reported) == nil)
}

@Test func aRadioStreamHasNoDuration() throws {
    let music = try #require(PlaybackState(player: .music, report: report(duration: .missing), at: reported))
    #expect(music.duration == nil)
    let spotify = try #require(PlaybackState(player: .spotify, report: report(duration: .number(0)), at: reported))
    #expect(spotify.duration == nil)
}

@Test func aMissingOrEmptyArtistIsNil() throws {
    #expect(PlaybackState(player: .music, report: report(artist: .missing), at: reported)?.artist == nil)
    #expect(PlaybackState(player: .music, report: report(artist: .text("")), at: reported)?.artist == nil)
}

@Test func onlyAReportWithAURLHasArtworkToFetch() {
    let url = "https://i.scdn.co/image/ab67616d0000b273"
    #expect(PlaybackState.artworkURL(in: report(artworkURL: .text(url))) == URL(string: url))
    #expect(PlaybackState.artworkURL(in: report(artworkURL: .text(""))) == nil)
    #expect(PlaybackState.artworkURL(in: report()) == nil)
}

@Test func theSameTrackKeepsItsArtwork() {
    let song = state(.music, playing: true)
    #expect(song.isSameTrack(as: state(.music, playing: false)))
    #expect(!song.isSameTrack(as: state(.music, title: "Next", playing: true)))
    #expect(!song.isSameTrack(as: state(.spotify, playing: true)))
    #expect(!song.isSameTrack(as: nil))
}

@Test func eachScriptTellsItsPlayerByBundleIDWithATimeout() {
    for player in ScriptedPlayer.allCases {
        for script in [player.stateScript, player.script(for: .togglePlayPause)] {
            #expect(script.hasPrefix("with timeout of 5 seconds\n"))
            #expect(script.contains(#"tell application id "\#(player.bundleIdentifier)""#))
            #expect(script.hasSuffix("end timeout"))
        }
    }
}

@Test func commandsUseEachPlayersOwnTerms() {
    #expect(ScriptedPlayer.music.script(for: .previousTrack).contains("\n        previous track\n"))
    #expect(ScriptedPlayer.music.script(for: .seek(to: 61.5)).contains("set player position to 61.5\n"))
    #expect(ScriptedPlayer.music.script(for: .seek(to: -3)).contains("set player position to 0.0\n"))
    #expect(ScriptedPlayer.music.script(for: .setRepeat(.all)).contains("set song repeat to all\n"))
    #expect(ScriptedPlayer.music.script(for: .setShuffle(.albums)).contains("set shuffle mode to albums\n        set shuffle enabled to true\n"))
    #expect(ScriptedPlayer.spotify.script(for: .setShuffle(.albums)).contains("set shuffling to true\n"))
    #expect(ScriptedPlayer.spotify.script(for: .setRepeat(.all)).contains("set repeating to true\n"))
    #expect(ScriptedPlayer.spotify.script(for: .setRepeat(.one)).contains("set repeating to false\n"))
    #expect(ScriptedPlayer.spotify.script(for: .setRepeat(.off)).contains("set repeating to false\n"))
}

@Test func onlyMusicNeedsAScriptForArtwork() {
    #expect(ScriptedPlayer.music.artworkScript?.contains("raw data of artwork 1 of current track") == true)
    #expect(ScriptedPlayer.spotify.artworkScript == nil)
}

@Test func nothingIsShownUntilAPlayerReports() {
    #expect(ScriptedNowPlaying().current == nil)
}

@Test func aPlayingPlayerComesBeforeAPausedOne() {
    var players = ScriptedNowPlaying()
    players.update(.music, state(.music, playing: true))
    players.update(.spotify, state(.spotify, playing: false))
    #expect(players.current?.bundleIdentifier == "com.apple.Music")
}

@Test func theLastPlayerToChangeComesFirstOtherwise() {
    var players = ScriptedNowPlaying()
    players.update(.music, state(.music, playing: true))
    players.update(.spotify, state(.spotify, playing: true))
    #expect(players.current?.bundleIdentifier == "com.spotify.client")
    players.update(.spotify, state(.spotify, playing: false))
    players.update(.music, state(.music, playing: false))
    #expect(players.current?.bundleIdentifier == "com.apple.Music")
}

@Test func aPlayerThatQuitsHandsBackToTheOther() {
    var players = ScriptedNowPlaying()
    players.update(.music, state(.music, playing: false))
    players.update(.spotify, state(.spotify, playing: true))
    players.update(.spotify, nil)
    #expect(players.current?.bundleIdentifier == "com.apple.Music")
    #expect(players.state(of: .spotify) == nil)
    players.update(.music, nil)
    #expect(players.current == nil)
}

@Test func spotifysRepeatButtonTurnsRepeatOnThenOff() {
    // Spotify reads back as off or all, so two presses of the button, which steps off, all, one, must end where they began.
    let on = RepeatMode.off.next
    #expect(ScriptedPlayer.spotify.script(for: .setRepeat(on)).contains("set repeating to true\n"))
    #expect(ScriptedPlayer.spotify.script(for: .setRepeat(on.next)).contains("set repeating to false\n"))
}
