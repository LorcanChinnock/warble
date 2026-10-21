import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: 1)

@Test func theFirstTrackShowsNoToast() {
    #expect(TrackToast.notice(from: nil, to: song) == nil)
}

@Test func aNewTrackShowsItsTitleAndArtistForTwoSeconds() throws {
    var next = song
    next.title = "Next song"
    next.artist = nil
    let notice = try #require(TrackToast.notice(from: song, to: next))
    #expect(notice.kind == .trackChanged)
    #expect(notice.content == TrackToast(title: "Next song"))
    #expect(notice.duration == 2)
}

@Test func anotherArtistOrAppIsANewTrack() {
    var cover = song
    cover.artist = "Someone else"
    #expect(TrackToast.notice(from: song, to: cover) != nil)
    var elsewhere = song
    elsewhere.bundleIdentifier = "com.spotify.client"
    #expect(TrackToast.notice(from: song, to: elsewhere) != nil)
}

@Test func pausingSeekingChangingSpeedOrLateArtShowsNoToast() {
    #expect(TrackToast.notice(from: song, to: song.playing(false, at: start + 5)) == nil)
    #expect(TrackToast.notice(from: song, to: song.seeked(to: 100, at: start + 5)) == nil)
    var faster = song
    faster.rate = 2
    #expect(TrackToast.notice(from: song, to: faster) == nil)
    var withArt = song
    withArt.artwork = Data([1, 2, 3])
    #expect(TrackToast.notice(from: song, to: withArt) == nil)
}

@Test func aQuickRunOfSkipsShowsOneToastForTheLastTrack() {
    var queue = ToastQueue<TrackToast>()
    var previous = song
    for (index, title) in ["Two", "Three", "Four", "Five"].enumerated() {
        var next = previous
        next.title = title
        if let notice = TrackToast.notice(from: previous, to: next) {
            queue.post(notice, at: start + Double(index) * 0.4)
        }
        previous = next
    }
    #expect(queue.current?.content == TrackToast(title: "Five", artist: "Artist"))
    #expect(queue.waiting.isEmpty)
    #expect(queue.deadline == start + 1.2 + 2)
}
