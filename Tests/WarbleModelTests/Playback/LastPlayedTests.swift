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

@Test func aSpotifyLinkResumesThroughItsURIAndOtherLinksAsTheyAre() {
    func resume(_ link: String?) -> URL? {
        LastPlayed(bundleIdentifier: "x", title: "T", link: link.flatMap(URL.init(string:))).resumeURL
    }
    #expect(resume("https://open.spotify.com/episode/Ab12") == URL(string: "spotify:episode:Ab12"))
    #expect(resume("https://example.com/watch") == URL(string: "https://example.com/watch"))
    #expect(resume(nil) == nil)
}

@Test func aTrackSavedBeforeLinksWereKeptStillDecodes() throws {
    let old = Data(#"{"bundleIdentifier":"com.apple.Music","title":"Song"}"#.utf8)
    let decoded = try JSONDecoder().decode(LastPlayed.self, from: old)
    #expect(decoded == LastPlayed(bundleIdentifier: "com.apple.Music", title: "Song"))
}

@Test func theLastTrackRoundTripsThroughJSON() throws {
    let track = LastPlayed(bundleIdentifier: "com.apple.Music", appName: "Music", title: "Song", artist: nil, artwork: Data([1, 2, 3]))
    let decoded = try JSONDecoder().decode(LastPlayed.self, from: JSONEncoder().encode(track))
    #expect(decoded == track)
}

@Test func aTabIsKeptOnlyWhenItsTitleNamesTheTrack() {
    func link(_ address: String, tab: String) -> URL? {
        Browser.link(address: address, tabTitle: tab, trackTitle: "Great Song")
    }
    #expect(link("https://example.com/watch?v=1", tab: "great song - YouTube") == URL(string: "https://example.com/watch?v=1"))
    #expect(link("https://example.com/watch?v=1", tab: "Inbox (3) - Mail") == nil)
    #expect(link("file:///Users/me/secret.html", tab: "Great Song") == nil)
    #expect(link("not an address", tab: "Great Song") == nil)
    #expect(Browser.link(address: "https://example.com", tabTitle: "Anything", trackTitle: "") == nil)
}

@Test func everyBrowserScriptNamesItsTabByBundleID() {
    for browser in Browser.allCases {
        #expect(browser.frontTabScript.contains("application id \"\(browser.bundleIdentifier)\""))
    }
    #expect(Browser.safari.frontTabScript.contains("current tab"))
    #expect(Browser.chrome.frontTabScript.contains("active tab"))
}
