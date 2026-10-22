import Foundation
import Testing
@testable import WarbleModel

// adapter-podcast is `stream --micros` output recorded on macOS 27 from an episode in Podcasts: playing, paused and
// played again from the adapter, then a seek to 10:00. The artwork's base64 is "artwork 1", and the episode and show
// are stand-ins.

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
/// Twenty minutes in, ten from the end.
private let episode = PlaybackState(
    bundleIdentifier: "com.apple.podcasts", title: "Episode", duration: 1800, elapsed: 1200, elapsedTimestamp: start,
    rate: 1, mediaType: .podcast
)
private let song = PlaybackState(
    bundleIdentifier: "com.apple.Music", title: "Song", duration: 240, elapsed: 60, elapsedTimestamp: start, rate: 1,
    mediaType: .music
)

private func fixture(_ name: String) throws -> [Data] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).jsonl")
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { Data($0.utf8) }
}

/// What the stream shows after the first `count` lines of `name`, or all of them.
private func replay(_ name: String, count: Int = .max) throws -> PlaybackState? {
    var stream = AdapterStream()
    for line in try fixture(name).prefix(count) {
        try stream.apply(line, at: start)
    }
    return stream.state
}

private func playing(_ playback: PlaybackState, podcastSkips: Bool = true) -> AppState {
    var state = AppState(podcastSkips: podcastSkips)
    _ = reduce(&state, .playbackReported(playback), now: start)
    return state
}

@Test func aRecordedPodcastReadsAsSpokenWord() throws {
    let podcast = try #require(try replay("adapter-podcast"))
    #expect(podcast.bundleIdentifier == "com.apple.podcasts")
    #expect(podcast.mediaType == .podcast)
    #expect(podcast.elapsed == 600)
    #expect(SpokenWord.contains(podcast))
    #expect(playing(podcast).skipsBySeconds)
}

@Test func aSongDoesntReadAsSpokenWord() throws {
    // Before the tab closes.
    let tab = try #require(try replay("adapter-safari", count: 3))
    #expect(tab.mediaType == nil)
    #expect(!SpokenWord.contains(tab))
    #expect(!SpokenWord.contains(song))
    #expect(!playing(song).skipsBySeconds)
}

@Test func anAppThatPlaysOnlySpeechIsSpokenWordWhateverItReports() {
    for app in ["com.apple.podcasts", "com.apple.iBooksX"] {
        let book = PlaybackState(bundleIdentifier: app, title: "Chapter 1", duration: 600, elapsedTimestamp: start, rate: 1)
        #expect(SpokenWord.contains(book))
    }
    var tab = song
    tab.bundleIdentifier = "com.apple.Safari"
    tab.mediaType = .audiobook
    #expect(SpokenWord.contains(tab))
}

@Test func theAdapterNamesEachMediaTypeByItsEnd() {
    #expect(MediaType(adapterValue: "MRMediaRemoteMediaTypePodcast") == .podcast)
    #expect(MediaType(adapterValue: "MRMediaRemoteMediaTypeAudioBook") == .audiobook)
    #expect(MediaType(adapterValue: "MRMediaRemoteMediaTypeMusic") == .music)
    #expect(MediaType(adapterValue: "kMRMediaRemoteNowPlayingInfoTypeAudio") == .other)
}

@Test func aSpotifyEpisodeIsAPodcast() throws {
    func report(_ uri: String) -> [ScriptValue] {
        [.text("playing"), .text("Title"), .text("Show"), .text("Album"), .number(1800), .number(30), .text("off"),
         .text("off"), .missing, .text(uri)]
    }
    let episode = try #require(PlaybackState(player: .spotify, report: report("spotify:episode:abc123"), at: start))
    let track = try #require(PlaybackState(player: .spotify, report: report("spotify:track:abc123"), at: start))
    #expect(episode.mediaType == .podcast)
    #expect(track.mediaType == .music)
}

@Test func aLiveStreamOfSpeechHasNoSkips() {
    var radio = episode
    radio.duration = nil
    #expect(!playing(radio).skipsBySeconds)
}

@Test func backFifteenNearTheStartSeeksToTheStart() {
    var opening = episode
    opening.elapsed = 5
    var state = playing(opening)
    let effects = reduce(&state, .skip(by: -SpokenWord.back), now: start + 2)
    #expect(effects == [.send(.seek(to: 0))])
    #expect(state.playback?.elapsed(at: start + 2) == 0)
}

@Test func forwardThirtyNearTheEndStopsAtTheEnd() {
    var closing = episode
    closing.elapsed = 1790
    var state = playing(closing)
    let effects = reduce(&state, .skip(by: SpokenWord.forward), now: start + 1)
    #expect(effects == [.send(.seek(to: 1800))])
    #expect(state.playback?.elapsed(at: start + 1) == 1800)
}

@Test func aSkipSeeksOnceFromWhereItIsAndShowsAtOnce() {
    var state = playing(episode)
    // Ten seconds on from the report, so 20:10, then 30 more.
    let effects = reduce(&state, .skip(by: SpokenWord.forward), now: start + 10)
    #expect(effects == [.send(.seek(to: 1240))])
    #expect(state.playback?.elapsed(at: start + 10) == 1240)
    #expect(state.playback?.elapsedTimestamp == start + 10)
}

@Test func withNothingPlayingASkipSendsNothing() {
    var state = AppState()
    #expect(reduce(&state, .skip(by: SpokenWord.forward), now: start).isEmpty)
    #expect(state.playback == nil)
    #expect(!state.skipsBySeconds)
    // Nor once the source reports nothing and the hide is pending.
    var stopping = playing(episode)
    _ = reduce(&stopping, .playbackReported(nil), now: start + 1)
    #expect(reduce(&stopping, .skip(by: -SpokenWord.back), now: start + 1.2).isEmpty)
}

@MainActor
@Test func theRunnerSendsASkipToTheSourceAsASeek() async {
    let source = FakeSource()
    let runner = makeRunner()
    runner.source = source
    var state = playing(episode)
    for effect in reduce(&state, .skip(by: -SpokenWord.back), now: start) {
        runner.perform(effect)
    }
    // The send runs on its own task; give it a turn.
    for _ in 0..<100 where await source.sent.isEmpty {
        await Task.yield()
    }
    #expect(await source.sent == [.seek(to: 1185)])
}

@Test func withTheSettingOffAPodcastKeepsPreviousAndNext() {
    #expect(!playing(episode, podcastSkips: false).skipsBySeconds)
}

@Test func turningTheSettingOnAndOffGivesAndTakesTheSkips() {
    var state = playing(episode, podcastSkips: false)
    _ = reduce(&state, .podcastSkipsChanged(true), now: start + 1)
    #expect(state.skipsBySeconds)
    _ = reduce(&state, .podcastSkipsChanged(false), now: start + 2)
    #expect(!state.skipsBySeconds)
}
