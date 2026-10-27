import Foundation
import Testing
import Synchronization
import WarbleModel
@testable import WarbleCore

private let response = Data("""
{"resultCount": 2, "results": [
  {"trackName": "Something Else", "artistName": "Someone", "artworkUrl100": "https://example.com/a/100x100bb.jpg"},
  {"trackName": "Musician", "artistName": "Porter Robinson", "artworkUrl100": "https://example.com/b/100x100bb.jpg"}
]}
""".utf8)

private func track(
    _ title: String, artist: String? = "Porter Robinson", app: String = "com.apple.Safari", artwork: Data? = Data([1])
) -> PlaybackState {
    PlaybackState(
        bundleIdentifier: app, title: title, artist: artist, elapsedTimestamp: Date(timeIntervalSince1970: 0), rate: 1,
        artwork: artwork
    )
}

@Test func theSearchNamesTheArtistAndTheSong() throws {
    let url = try #require(CoverArt.searchURL(for: .init(title: "Musician", artist: "Porter Robinson")))
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items.first { $0.name == "term" }?.value == "Porter Robinson Musician")
    #expect(items.first { $0.name == "entity" }?.value == "song")
}

@Test func theCoverIsTheFirstResultWhoseSongAndArtistMatchAtSixHundredPixels() throws {
    let url = CoverArt.coverURL(in: response, for: .init(title: "Musician", artist: "Porter Robinson"))
    #expect(url?.absoluteString == "https://example.com/b/600x600bb.jpg")
}

@Test func aVideoTitleThatHoldsTheArtistAndSongStillMatches() {
    let query = CoverArt.Query(title: "Porter Robinson - Musician (Official Video)", artist: "PorterRobinsonVEVO")
    #expect(CoverArt.coverURL(in: response, for: query) != nil)
}

@Test func aResultForADifferentSongIsNotUsed() {
    #expect(CoverArt.coverURL(in: response, for: .init(title: "Cooking pasta", artist: "Some Channel")) == nil)
}

@Test func aBrokenResponseHasNoCover() {
    #expect(CoverArt.coverURL(in: Data("nope".utf8), for: .init(title: "Musician", artist: nil)) == nil)
}

@Test func aBrowserTrackHasNoArtworkUntilItsCoverComesThenShowsTheCover() async {
    let (input, continuation) = AsyncStream<PlaybackState?>.makeStream()
    let cover = Data([9])
    var shown = CoverArt.replacing(input) { _ in cover }.makeAsyncIterator()
    continuation.yield(track("Musician"))
    let first = await shown.next()
    #expect(first??.artwork == nil)
    let second = await shown.next()
    #expect(second??.artwork == cover)
    continuation.finish()
}

@Test func withNoCoverTheBrowsersOwnPictureComesBack() async {
    let (input, continuation) = AsyncStream<PlaybackState?>.makeStream()
    var shown = CoverArt.replacing(input) { _ in nil }.makeAsyncIterator()
    continuation.yield(track("Musician"))
    _ = await shown.next()
    #expect(await shown.next()??.artwork == Data([1]))
    continuation.finish()
}

@Test func aSongIsLookedUpOnceHoweverOftenItReports() async {
    let (input, continuation) = AsyncStream<PlaybackState?>.makeStream()
    let lookups = Mutex(0)
    var shown = CoverArt.replacing(input) { _ in
        lookups.withLock { $0 += 1 }
        return Data([9])
    }.makeAsyncIterator()
    continuation.yield(track("Musician"))
    _ = await shown.next()
    _ = await shown.next()
    continuation.yield(track("Musician"))
    #expect(await shown.next()??.artwork == Data([9]))
    #expect(lookups.withLock { $0 } == 1)
    continuation.finish()
}

@Test func otherAppsKeepTheirOwnArtworkWithNoLookup() async {
    let (input, continuation) = AsyncStream<PlaybackState?>.makeStream()
    var shown = CoverArt.replacing(input) { _ in
        Issue.record("Music's art should not be looked up")
        return nil
    }.makeAsyncIterator()
    continuation.yield(track("Musician", app: "com.apple.Music"))
    #expect(await shown.next()??.artwork == Data([1]))
    continuation.finish()
}
