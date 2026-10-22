import Foundation
import Testing
@testable import WarbleModel

private func excerpt(_ lrc: String, at position: TimeInterval) -> LyricsExcerpt? {
    LyricsExcerpt(Lyrics(lrc: lrc)!, at: position)
}

private let verse = """
[00:01.00] One
[00:02.00] Two
[00:03.00]
[00:04.00] Three
[00:05.00] Four
[00:06.00] Five
"""

@Test func theExcerptShowsTheLineBeingSungWithOneBeforeAndUpToThreeAfter() throws {
    let lines = try #require(excerpt(verse, at: 4.5))
    #expect(lines.rows.map(\.text) == ["Two", "Three", "Four", "Five"])
    #expect(lines.rows.map(\.isCurrent) == [false, true, false, false])
    #expect(lines.missingBefore == 0)
}

@Test func beforeTheFirstLineTheNextTakesTheMiddleWithNoneCurrent() throws {
    let lines = try #require(excerpt(verse, at: 0))
    #expect(lines.rows.map(\.text) == ["One", "Two", "Three", "Four"])
    #expect(lines.rows.allSatisfy { !$0.isCurrent })
    #expect(lines.missingBefore == 1)
}

@Test func inAGapTheNextLineTakesTheMiddleAndTheGapIsLeftOut() throws {
    let lines = try #require(excerpt(verse, at: 3.5))
    #expect(lines.rows.map(\.text) == ["Two", "Three", "Four", "Five"])
    #expect(lines.rows.allSatisfy { !$0.isCurrent })
}

@Test func theLastLineShowsWithNoneAfterIt() throws {
    let lines = try #require(excerpt(verse, at: 60))
    #expect(lines.rows.map(\.text) == ["Four", "Five"])
    #expect(lines.rows.last?.isCurrent == true)
}

@Test func aGapAfterTheLastLineLeavesItAboveWithNoneCurrent() throws {
    let lines = try #require(excerpt(verse + "\n[00:07.00]", at: 60))
    #expect(lines.rows.map(\.text) == ["Five"])
    #expect(lines.rows.allSatisfy { !$0.isCurrent })
}

@Test func eachRowKeepsItsLinesPlaceSoItMovesUpAsTheSongGoesOn() throws {
    let earlier = try #require(excerpt(verse, at: 4.5))
    let later = try #require(excerpt(verse, at: 5.5))
    #expect(earlier.rows.first { $0.text == "Four" }?.id == later.rows.first { $0.text == "Four" }?.id)
}

@Test func lyricsWithNoWordsHaveNoExcerpt() {
    #expect(excerpt("[00:01.00]\n[00:02.00]", at: 1.5) == nil)
}
