import Foundation
import Testing
@testable import WarbleModel

// The fixtures are answers from LRCLIB's /api/get, saved as sent, for songs whose words are in the public domain.
// amazing-grace (Dave Fenley) and scarborough-fair (Mat Williams) have synced lyrics, each ending on an empty line;
// amazing-grace-instrumental is marked instrumental and has none.

private struct Answer: Decodable {
    var plainLyrics: String?
    var syncedLyrics: String?
}

private func fixture(_ name: String) throws -> Answer {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/lrclib-\(name).json")
    return try JSONDecoder().decode(Answer.self, from: Data(contentsOf: url))
}

private let verse = """
[ar:Artist]
[ti:Song]
[00:05.00] First
[00:10.50] Second
[00:20.00]
[00:30.00] Third
"""

private func lyrics(_ lrc: String) throws -> Lyrics {
    try #require(Lyrics(lrc: lrc))
}

@Test func linesParseInOrderWithTheirTimes() throws {
    #expect(try lyrics(verse).lines == [
        .init(time: 5, text: "First"),
        .init(time: 10.5, text: "Second"),
        .init(time: 20, text: ""),
        .init(time: 30, text: "Third"),
    ])
}

@Test func timestampsTakeAnyFractionUpToMilliseconds() throws {
    let lrc = "[00:01] a\n[00:02.5] b\n[00:03.25] c\n[00:04.125] d\n[00:05:50] e\n[100:00.00] f\n[00:06.12345] g"
    #expect(try lyrics(lrc).lines.map(\.time) == [1, 2.5, 3.25, 4.125, 5.5, 6.123, 6000])
}

@Test func aLineWithSeveralTimestampsRepeatsAtEach() throws {
    let lrc = "[00:12.00][00:48.50] Chorus\n[00:30.00] Verse"
    #expect(try lyrics(lrc).lines == [
        .init(time: 12, text: "Chorus"),
        .init(time: 30, text: "Verse"),
        .init(time: 48.5, text: "Chorus"),
    ])
}

@Test func linesOutOfOrderAreSortedAndTiesKeepTheFilesOrder() throws {
    let lrc = "[00:20.00] Later\n[00:10.00] Sooner\n[00:10.00] Sooner, translated"
    #expect(try lyrics(lrc).lines.map(\.text) == ["Sooner", "Sooner, translated", "Later"])
}

@Test func aPositiveOffsetShowsEveryLineEarlier() throws {
    let lrc = "[00:05.00] First\n[00:10.00] Second\n[offset:+500]"
    #expect(try lyrics(lrc).lines.map(\.time) == [4.5, 9.5])
}

@Test func aNegativeOffsetShowsEveryLineLater() throws {
    #expect(try lyrics("[offset: -250]\n[00:05.00] First").lines.map(\.time) == [5.25])
}

@Test func anOffsetNeverMovesALineBeforeTheStart() throws {
    #expect(try lyrics("[offset:+2000]\n[00:01.00] First\n[00:03.00] Second").lines.map(\.time) == [0, 1])
}

@Test func otherTagsAndUntimedLinesAreDropped() throws {
    let lrc = "[ar:Artist]\n[length: 03:20]\nJust words\n[by:Someone]\n[00:01.00] Kept"
    #expect(try lyrics(lrc).lines == [.init(time: 1, text: "Kept")])
}

@Test func wordTimesAreDroppedFromTheText() throws {
    let lrc = "[00:01.00] <00:01.00>One <00:01.50>two <threes> <00:02.00>four"
    #expect(try lyrics(lrc).lines.map(\.text) == ["One two <threes> four"])
}

@Test func windowsLineEndingsAndAByteOrderMarkParse() throws {
    #expect(try lyrics("\u{FEFF}[00:01.00] One\r\n[00:02.00] Two\r\n").lines.map(\.text) == ["One", "Two"])
}

@Test func textWithNoTimedLinesIsNoLyrics() {
    #expect(Lyrics(lrc: "") == nil)
    #expect(Lyrics(lrc: "\n\n") == nil)
    #expect(Lyrics(lrc: "Plain lyrics\nwith no times") == nil)
    #expect(Lyrics(lrc: "[ar:Artist]\n[ti:Song]\n[offset:+100]") == nil)
}

@Test func malformedTimestampsAreDropped() throws {
    let lrc = "[0a:01.00] a\n[00:1x] b\n[00:01.] c\n[:01.00] d\n[00:123.00] e\n[00:01.00 f\n[00:02.00] Kept"
    #expect(try lyrics(lrc).lines == [.init(time: 2, text: "Kept")])
}

@Test func beforeTheFirstLineNothingShows() throws {
    let lyrics = try lyrics(verse)
    #expect(lyrics.line(at: 0) == nil)
    #expect(lyrics.line(at: 4.999) == nil)
    #expect(lyrics.nextChange(after: 0) == 5)
}

@Test func aLineShowsFromItsTimeUntilTheNext() throws {
    let lyrics = try lyrics(verse)
    #expect(lyrics.line(at: 5)?.text == "First")
    #expect(lyrics.line(at: 7)?.text == "First")
    #expect(lyrics.line(at: 10.499)?.text == "First")
    #expect(lyrics.line(at: 10.5)?.text == "Second")
    #expect(lyrics.line(at: 25)?.text == "")
}

@Test func afterTheLastLineItStaysWithNoMoreChanges() throws {
    let lyrics = try lyrics(verse)
    #expect(lyrics.line(at: 30)?.text == "Third")
    #expect(lyrics.line(at: 3600)?.text == "Third")
    #expect(lyrics.nextChange(after: 30) == nil)
    #expect(lyrics.nextChange(after: 3600) == nil)
}

@Test func theNextChangeIsTheNextLinesTime() throws {
    let lyrics = try lyrics(verse)
    #expect(lyrics.nextChange(after: 5) == 10.5)
    #expect(lyrics.nextChange(after: 7) == 10.5)
    #expect(lyrics.nextChange(after: 10.5) == 20)
    #expect(lyrics.nextChange(after: 29.9) == 30)
}

@Test func linesThatStartTogetherShowTheLastAndChangeOnce() throws {
    let lyrics = try lyrics("[00:01.00] One\n[00:05.00] Two\n[00:05.00] Two, translated\n[00:09.00] Three")
    #expect(lyrics.line(at: 5)?.text == "Two, translated")
    #expect(lyrics.nextChange(after: 1) == 5)
    #expect(lyrics.nextChange(after: 5) == 9)
}

@Test func anLRCLIBAnswerParsesEveryLine() throws {
    let lyrics = try lyrics(try #require(try fixture("amazing-grace").syncedLyrics))
    #expect(lyrics.lines.count == 22)
    #expect(lyrics.lines.first == .init(time: 7.89, text: "Amazing Grace"))
    #expect(lyrics.line(at: 14)?.text == "How sweet the sound")
    #expect(lyrics.nextChange(after: 14) == 16.57)
    #expect(lyrics.line(at: 157)?.text == "Amen")
}

@Test func anLRCLIBAnswerClearsTheLastLineBeforeTheSongEnds() throws {
    let lyrics = try lyrics(try #require(try fixture("scarborough-fair").syncedLyrics))
    #expect(lyrics.line(at: 180)?.text == "Then she'll be a true love of mine")
    #expect(lyrics.nextChange(after: 180) == 182.63)
    #expect(lyrics.line(at: 182.63)?.text == "")
    #expect(lyrics.nextChange(after: 182.63) == nil)
}

@Test func anLRCLIBAnswerWithOnlyPlainLyricsIsNoLyrics() throws {
    let answer = try fixture("scarborough-fair")
    #expect(Lyrics(lrc: try #require(answer.plainLyrics)) == nil)
}

@Test func anInstrumentalLRCLIBAnswerIsNoLyrics() throws {
    let answer = try fixture("amazing-grace-instrumental")
    #expect(answer.syncedLyrics == nil)
    #expect(Lyrics(lrc: answer.syncedLyrics ?? "") == nil)
}
