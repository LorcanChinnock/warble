import Foundation
import Testing
@testable import WarbleModel

private func playing(
    title: String = "Amazing Grace",
    artist: String? = "Dave Fenley",
    album: String? = "Amazing Grace",
    duration: TimeInterval? = 172
) -> PlaybackState {
    PlaybackState(
        bundleIdentifier: "com.apple.Music", title: title, artist: artist, album: album, duration: duration,
        elapsedTimestamp: Date(timeIntervalSince1970: 0), rate: 1
    )
}

@Test func aQueryTakesTheTracksArtistTitleAlbumAndLength() {
    #expect(LyricsQuery(playing()) == LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace", album: "Amazing Grace", duration: 172))
}

@Test func aQueryRoundsTheLengthToWholeSeconds() {
    #expect(LyricsQuery(playing(duration: 171.6))?.duration == 172)
    #expect(LyricsQuery(playing(duration: 172.4))?.duration == 172)
}

@Test func aQueryWithoutAnAlbumLeavesItOut() {
    #expect(LyricsQuery(playing(album: nil))?.album == nil)
    #expect(LyricsQuery(playing(album: "  "))?.album == nil)
}

@Test func aQueryWithoutALengthLeavesItOut() {
    #expect(LyricsQuery(playing(duration: nil))?.duration == nil)
    #expect(LyricsQuery(playing(duration: 0))?.duration == nil)
}

@Test func aLengthNoSongCouldHaveIsLeftOutRatherThanTrapping() {
    for duration in [-5, 86_401, .infinity, .nan, .greatestFiniteMagnitude] {
        #expect(LyricsQuery(playing(duration: duration))?.duration == nil)
    }
}

@Test func aTrackWithoutAnArtistOrATitleHasNoQuery() {
    #expect(LyricsQuery(playing(artist: nil)) == nil)
    #expect(LyricsQuery(playing(artist: " ")) == nil)
    #expect(LyricsQuery(playing(title: "")) == nil)
}

@Test func aQueryTrimsEachField() {
    #expect(LyricsQuery(playing(title: " Amazing Grace\n", artist: "Dave Fenley ", album: " Amazing Grace")) == LyricsQuery(playing()))
}

@Test func everyReportOfOneTrackHasTheSameCacheKey() throws {
    let start = try #require(LyricsQuery(playing()))
    var later = playing()
    later.elapsed = 90
    later.rate = 0
    later.artwork = Data([1, 2, 3])
    #expect(try #require(LyricsQuery(later)).cacheKey == start.cacheKey)
}

@Test func theCacheKeyChangesWithEveryField() {
    let keys = [
        LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace", album: "Amazing Grace", duration: 172),
        LyricsQuery(artist: "Mat Williams", title: "Amazing Grace", album: "Amazing Grace", duration: 172),
        LyricsQuery(artist: "Dave Fenley", title: "Scarborough Fair", album: "Amazing Grace", duration: 172),
        LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace", album: nil, duration: 172),
        LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace", album: "Amazing Grace", duration: 173),
        LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace", album: "Amazing Grace", duration: nil),
    ].map(\.cacheKey)
    #expect(Set(keys).count == keys.count)
}

@Test func fieldsCantRunIntoEachOtherInTheCacheKey() {
    let one = LyricsQuery(artist: "a1:b", title: "c")
    let other = LyricsQuery(artist: "a", title: "b1:c")
    #expect(one.cacheKey != other.cacheKey)
}
