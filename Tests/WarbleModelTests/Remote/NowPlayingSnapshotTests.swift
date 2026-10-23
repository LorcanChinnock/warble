import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func state(_ playback: PlaybackState?) -> AppState {
    var state = AppState()
    _ = reduce(&state, .playbackReported(playback), now: start)
    return state
}

private let song = PlaybackState(
    bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", album: "Album", duration: 200.4, elapsed: 10,
    elapsedTimestamp: start, rate: 1, shuffle: .songs, repeatMode: .all
)

@Test func aSnapshotOfAPlayingTrackRunsThePositionOn() {
    let snapshot = NowPlayingSnapshot(state(song), volume: 0.4, at: start + 5.5)
    #expect(snapshot.status == .playing)
    #expect(snapshot.title == "Song")
    #expect(snapshot.artist == "Artist")
    #expect(snapshot.album == "Album")
    #expect(snapshot.app == "com.apple.Music")
    #expect(snapshot.position == 15)
    #expect(snapshot.duration == 200)
    #expect(snapshot.shuffle == "songs")
    #expect(snapshot.repeatMode == "all")
    #expect(snapshot.volume == 40)
}

@Test func aSnapshotOfAPausedTrackHoldsThePosition() {
    var paused = song
    paused.rate = 0
    let snapshot = NowPlayingSnapshot(state(paused), volume: nil, at: start + 60)
    #expect(snapshot.status == .paused)
    #expect(snapshot.position == 10)
    #expect(snapshot.volume == nil)
}

@Test func aSnapshotWithNothingPlayingHasOnlyAStatusAndTheVolume() {
    let snapshot = NowPlayingSnapshot(state(nil), volume: 0.5, at: start)
    #expect(snapshot.status == .stopped)
    #expect(snapshot.title == nil)
    #expect(snapshot.json == #"{"status":"stopped","volume":50}"#)
    #expect(NowPlayingSnapshot(state(nil), volume: nil, at: start).json == #"{"status":"stopped"}"#)
}

@Test func theJSONKeysAreFixed() {
    let snapshot = NowPlayingSnapshot(state(song), volume: 0.4, at: start)
    #expect(snapshot.json == #"{"album":"Album","app":"com.apple.Music","artist":"Artist","duration":200,"position":10,"repeat":"all","shuffle":"songs","status":"playing","title":"Song","volume":40}"#)
}

@Test func aTrackWithLessToSayLeavesOutItsKeys() {
    let bare = PlaybackState(bundleIdentifier: "com.google.Chrome", title: "Video", elapsedTimestamp: start, rate: 1)
    #expect(NowPlayingSnapshot(state(bare), volume: nil, at: start).json == #"{"app":"com.google.Chrome","position":0,"status":"playing","title":"Video"}"#)
}

@Test func theJSONRoundTrips() throws {
    let snapshot = NowPlayingSnapshot(state(song), volume: 0.4, at: start)
    let back = try JSONDecoder().decode(NowPlayingSnapshot.self, from: Data(snapshot.json.utf8))
    #expect(back == snapshot)
}

@Test func theTextReadsForAPerson() {
    #expect(NowPlayingSnapshot(state(song), volume: 0.4, at: start).text == """
        Playing: Song by Artist
        Album: Album
        Position: 0:10 of 3:20
        App: com.apple.Music
        Volume: 40%
        """)
    #expect(NowPlayingSnapshot(state(nil), volume: nil, at: start).text == "Nothing is playing.")
    var live = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Radio", elapsedTimestamp: start, rate: 0)
    live.duration = nil
    #expect(NowPlayingSnapshot(state(live), volume: nil, at: start).text == "Paused: Radio\nPosition: 0:00\nApp: com.apple.Music")
}
