import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: 1)

@Test func theFirstTrackIsAlwaysRemembered() {
    #expect(LastPlayed.changes(from: nil, to: song))
}

@Test func pausingSeekingOrChangingSpeedIsntANewTrack() {
    #expect(!LastPlayed.changes(from: song, to: song.playing(false, at: start + 5)))
    #expect(!LastPlayed.changes(from: song, to: song.seeked(to: 100, at: start + 5)))
    var faster = song
    faster.rate = 2
    #expect(!LastPlayed.changes(from: song, to: faster))
}

@Test func aNewTrackOrItsArtArrivingIsRemembered() {
    var next = song
    next.title = "Next song"
    #expect(LastPlayed.changes(from: song, to: next))
    var elsewhere = song
    elsewhere.bundleIdentifier = "com.spotify.client"
    #expect(LastPlayed.changes(from: song, to: elsewhere))
    var withArt = song
    withArt.artwork = Data([1, 2, 3])
    #expect(LastPlayed.changes(from: song, to: withArt))
}

@Test func theLastTrackRoundTripsThroughJSON() throws {
    let track = LastPlayed(bundleIdentifier: "com.apple.Music", appName: "Music", title: "Song", artist: nil, artwork: Data([1, 2, 3]))
    let decoded = try JSONDecoder().decode(LastPlayed.self, from: JSONEncoder().encode(track))
    #expect(decoded == track)
}
