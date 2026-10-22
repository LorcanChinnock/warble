import Foundation
import Testing
@testable import WarbleModel

// The fixtures are `stream --micros` output recorded on macOS 27, with each image's base64 swapped for a short stand-in
// ("artwork 1", "artwork 2" and so on). adapter-safari is a local page with an <audio> element and Media Session
// metadata: play, pause and play again from the adapter, a seek to 2:00, then the tab closed. adapter-youtube is a
// YouTube tab in Safari: an ad, the video after it, pause and play, the tab closed, then a live stream in another tab.

private func fixture(_ name: String) throws -> [Data] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).jsonl")
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { Data($0.utf8) }
}

private func epoch(_ micros: Double) -> Date {
    Date(timeIntervalSince1970: micros / 1_000_000)
}

/// Applies `lines` in order, each received at `date`.
private func replay(_ lines: ArraySlice<Data>, at date: Date = epoch(1_792_364_900_000_000)) throws -> AdapterStream {
    var stream = AdapterStream()
    for line in lines {
        try stream.apply(line, at: date)
    }
    return stream
}

private func line(diff: Bool, _ payload: String) -> Data {
    Data(#"{"type":"data","diff":\#(diff),"payload":{\#(payload)}}"#.utf8)
}

private let playingLine = line(diff: false, #""bundleIdentifier":"com.apple.Music","title":"Song","playing":true,"playbackRate":1,"elapsedTimeMicros":30000000,"timestampEpochMicros":1792364800000000"#)

@Test func nothingPlayingIsAnEmptyPayload() throws {
    var stream = AdapterStream()
    #expect(try !stream.apply(line(diff: false, ""), at: .now))
    #expect(stream.state == nil)
}

@Test func aSafariTabShowsAsSafariWithItsTrack() throws {
    let lines = try fixture("adapter-safari")
    let state = try #require(try replay(lines[...1]).state)
    #expect(state.bundleIdentifier == "com.apple.Safari")
    #expect(state.title == "Warble Test Tone")
    #expect(state.artist == "Test Artist")
    #expect(state.album == "Test Album")
    #expect(state.duration == 599.975328)
    #expect(state.elapsed == 0)
    #expect(state.elapsedTimestamp == epoch(1_792_364_847_639_636))
    #expect(state.isPlaying)
    #expect(state.artwork == nil)
}

@Test func artworkArrivesOnTheLineAfterTheTitle() throws {
    let lines = try fixture("adapter-safari")
    var stream = try replay(lines[...1])
    #expect(try stream.apply(lines[2], at: .now))
    #expect(stream.state?.artwork == Data("artwork 1".utf8))
    #expect(stream.state?.title == "Warble Test Tone")
}

@Test func aPauseHoldsThePositionUntilTheAdapterReportsIt() throws {
    let lines = try fixture("adapter-safari")
    let started = epoch(1_792_364_847_639_636)
    var stream = try replay(lines[...2])
    // `playing` turns false on its own line, before the line with the position.
    try stream.apply(lines[3], at: started + 3)
    let paused = try #require(stream.state)
    #expect(!paused.isPlaying)
    #expect(abs(paused.elapsed(at: started + 60) - 3) < 0.000_001)
    // The image type changes on a line of its own and changes nothing Warble shows.
    try stream.apply(lines[4], at: started + 3.1)
    #expect(stream.state?.elapsed(at: started + 60) == 2.761531)
    #expect(try !stream.apply(lines[5], at: started + 3.2))
}

@Test func playingAgainRunsOnFromWhereItPaused() throws {
    let lines = try fixture("adapter-safari")
    let resumed = epoch(1_792_364_852_700_000)
    var stream = try replay(lines[...5])
    try stream.apply(lines[6], at: resumed)
    let state = try #require(stream.state)
    #expect(state.isPlaying)
    #expect(abs(state.elapsed(at: resumed + 10) - 12.761531) < 0.000_001)
}

@Test func aSeekMovesThePosition() throws {
    let lines = try fixture("adapter-safari")
    let state = try #require(try replay(lines[...13]).state)
    #expect(state.isPlaying)
    #expect(state.elapsed == 120)
    #expect(state.elapsedTimestamp == epoch(1_792_364_854_853_759))
}

@Test func closingTheTabShowsNothing() throws {
    let lines = try fixture("adapter-safari")
    var stream = try replay(lines[...14])
    #expect(try stream.apply(lines[15], at: .now))
    #expect(stream.state == nil)
}

@Test func anEmptyAlbumCountsAsNone() throws {
    let lines = try fixture("adapter-youtube")
    let state = try #require(try replay(lines[...1]).state)
    #expect(state.title == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
    #expect(state.album == nil)
}

@Test func theVideoAfterAnAdReplacesItWithItsOwnArtwork() throws {
    let lines = try fixture("adapter-youtube")
    let ad = try #require(try replay(lines[...5]).state)
    #expect(ad.title == "NEW Pampers Baby-Dry. Leak-proof for better sleep.")
    #expect(ad.artwork == Data("artwork 2".utf8))
    let video = try #require(try replay(lines[...11]).state)
    #expect(video.title == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
    #expect(video.artwork == Data("artwork 1".utf8))
    #expect(video.isPlaying)
}

@Test func aDurationCanArriveAfterTheTrack() throws {
    let lines = try fixture("adapter-youtube")
    #expect(try replay(lines[...11]).state?.duration == nil)
    #expect(try replay(lines[...12]).state?.duration == 213.061)
}

@Test func aLiveStreamReportsItsRecordingWindowAsItsDuration() throws {
    let lines = try fixture("adapter-youtube")
    let state = try #require(try replay(lines[...28]).state)
    #expect(state.title == "lofi hip hop radio 📚 beats to relax/study to")
    #expect(state.elapsed == 46_790)
    #expect(state.duration == 50_390.010793)
}

@Test func aDiffSettingAKeyToNullRemovesIt() throws {
    var stream = AdapterStream()
    try stream.apply(line(diff: false, #""bundleIdentifier":"com.apple.Music","title":"Song","artist":"Artist","playing":true"#), at: .now)
    #expect(stream.state?.artist == "Artist")
    try stream.apply(line(diff: true, #""artist":null"#), at: .now)
    #expect(stream.state?.artist == nil)
    #expect(stream.state?.title == "Song")
}

@Test func aFullPayloadForgetsKeysItDoesntHave() throws {
    var stream = AdapterStream()
    try stream.apply(line(diff: false, #""bundleIdentifier":"com.apple.Music","title":"One","artist":"Artist","artworkData":"YXJ0""#), at: .now)
    try stream.apply(line(diff: false, #""bundleIdentifier":"com.apple.Music","title":"Two""#), at: .now)
    #expect(stream.state?.title == "Two")
    #expect(stream.state?.artist == nil)
    #expect(stream.state?.artwork == nil)
}

@Test func aTrackWithoutATitleShowsNothing() throws {
    var stream = AdapterStream()
    try stream.apply(line(diff: false, #""bundleIdentifier":"com.apple.Music","title":"","playing":true"#), at: .now)
    #expect(stream.state == nil)
}

@Test func aTrackWithoutAnAppShowsNothing() throws {
    var stream = AdapterStream()
    try stream.apply(line(diff: false, #""title":"Song","playing":true"#), at: .now)
    #expect(stream.state == nil)
}

@Test func aTrackWithoutATimestampStartsWhenItArrives() throws {
    let received = epoch(1_792_364_800_000_000)
    var stream = AdapterStream()
    try stream.apply(line(diff: false, #""bundleIdentifier":"com.apple.Music","title":"Song","playing":true,"elapsedTimeMicros":5000000"#), at: received)
    #expect(stream.state?.elapsed(at: received + 1) == 6)
    // A later line that changes something else doesn't move the start.
    try stream.apply(line(diff: true, #""artist":"Artist""#), at: received + 10)
    #expect(stream.state?.elapsed(at: received + 1) == 6)
}

@Test func doubleSpeedRunsOnAtTheReportedRate() throws {
    var stream = AdapterStream()
    try stream.apply(playingLine, at: .now)
    try stream.apply(line(diff: true, #""playbackRate":2"#), at: .now)
    #expect(stream.state?.rate == 2)
}

@Test func shuffleAndRepeatUseMediaRemotesNumbers() throws {
    var stream = AdapterStream()
    try stream.apply(playingLine, at: .now)
    #expect(stream.state?.shuffle == nil)
    #expect(stream.state?.repeatMode == nil)
    try stream.apply(line(diff: true, #""shuffleMode":3,"repeatMode":2"#), at: .now)
    #expect(stream.state?.shuffle == .songs)
    #expect(stream.state?.repeatMode == .one)
    try stream.apply(line(diff: true, #""shuffleMode":1,"repeatMode":3"#), at: .now)
    #expect(stream.state?.shuffle == .off)
    #expect(stream.state?.repeatMode == .all)
    try stream.apply(line(diff: true, #""shuffleMode":0,"repeatMode":0"#), at: .now)
    #expect(stream.state?.shuffle == nil)
    #expect(stream.state?.repeatMode == nil)
}

@Test func aMalformedLineThrowsAndChangesNothing() throws {
    var stream = AdapterStream()
    try stream.apply(playingLine, at: .now)
    let before = stream.state
    #expect(throws: (any Error).self) { try stream.apply(Data("{\"type\":\"data\",".utf8), at: .now) }
    #expect(stream.state == before)
}

@Test func linesOfAnotherTypeAreIgnored() throws {
    var stream = AdapterStream()
    try stream.apply(playingLine, at: .now)
    #expect(try !stream.apply(Data(#"{"type":"error","diff":false,"payload":{}}"#.utf8), at: .now))
    #expect(stream.state?.title == "Song")
}

@Test func commandsBecomeAdapterArguments() {
    #expect(PlaybackCommand.play.adapterArguments == ["send", "0"])
    #expect(PlaybackCommand.pause.adapterArguments == ["send", "1"])
    #expect(PlaybackCommand.togglePlayPause.adapterArguments == ["send", "2"])
    #expect(PlaybackCommand.nextTrack.adapterArguments == ["send", "4"])
    #expect(PlaybackCommand.previousTrack.adapterArguments == ["send", "5"])
    #expect(PlaybackCommand.seek(to: 120.5).adapterArguments == ["seek", "120500000"])
    #expect(PlaybackCommand.seek(to: -3).adapterArguments == ["seek", "0"])
    #expect(PlaybackCommand.setShuffle(.off).adapterArguments == ["shuffle", "1"])
    #expect(PlaybackCommand.setShuffle(.albums).adapterArguments == ["shuffle", "2"])
    #expect(PlaybackCommand.setShuffle(.songs).adapterArguments == ["shuffle", "3"])
    #expect(PlaybackCommand.setRepeat(.off).adapterArguments == ["repeat", "1"])
    #expect(PlaybackCommand.setRepeat(.one).adapterArguments == ["repeat", "2"])
    #expect(PlaybackCommand.setRepeat(.all).adapterArguments == ["repeat", "3"])
}
