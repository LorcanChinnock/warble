import Foundation
import Testing
@testable import WarbleModel

/// One point a character, so a width in points is a length in characters.
private func line(_ title: String, _ artist: String? = nil, width: Double = 22) -> TrackTitle.Line {
    TrackTitle.line(title: title, artist: artist, width: width) { Double($0.count) }
}

@Test(arguments: [
    ("Heroes - Remastered 2009", "Heroes"),
    ("Heroes - 2017 Remaster", "Heroes"),
    ("Song (feat. Someone)", "Song"),
    ("Song [Live at Wembley]", "Song"),
    ("Song (Official Video)", "Song"),
    ("Song (Remastered) [Live in Paris]", "Song"),
    ("Song (feat. A) - Single Version", "Song"),
    ("Song (Live)", "Song"),
])
func trimmingCutsTrailingTags(title: String, trimmed: String) {
    #expect(TrackTitle.trimmed(title) == trimmed)
}

@Test(arguments: [
    "Wings - Live and Let Die",
    "Song (Part 2)",
    "Song (Reprise)",
    "Live Forever",
    "(Official Video)",
    "Remastered",
    "Song [Live at Wembley",
    "Song Live at Wembley)",
    "",
])
func trimmingLeavesWhatIsntATag(title: String) {
    #expect(TrackTitle.trimmed(title) == title)
}

@Test func aTitleThatIsOnlyTagsKeepsTheLastOfThem() {
    #expect(TrackTitle.trimmed("(Official Video) (feat. A)") == "(Official Video)")
}

@Test func titleAndArtistShowTogetherWhenTheyFit() {
    #expect(line("Heroes", "David Bowie") == .titleAndArtist("Heroes — David Bowie"))
}

@Test func theArtistGoesBeforeTheTitleDoes() {
    #expect(line("Heroes", "David Bowie and The Spiders") == .title("Heroes"))
    #expect(line("Heroes", nil) == .title("Heroes"))
    #expect(line("Heroes", "  ") == .title("Heroes"))
}

@Test func aTitleThatStillDoesntFitFades() {
    #expect(line("The Long and Winding Road to Nowhere", "Artist") == .faded("The Long and Winding Road to Nowhere"))
    #expect(line("The Long and Winding Road to Nowhere").isCut)
}

@Test func tagsAreCutBeforeMeasuring() {
    #expect(line("Heroes (Official Video)", "Bowie") == .titleAndArtist("Heroes — Bowie"))
    #expect(line("Heroes (2017 Remaster)") == .title("Heroes"))
}

@Test func aTitleExactlyAsWideAsTheNotchFits() {
    #expect(line(String(repeating: "a", count: 22)) == .title(String(repeating: "a", count: 22)))
    #expect(line(String(repeating: "a", count: 23)).isCut)
}

@Test func theScrollWaitsMovesOnceHoldsAndSnapsBack() {
    let scroll = NotchMotion.titleScroll(travel: 36)
    let wait = NotchMotion.titleScrollWait
    let moves = 36 / NotchMotion.titleScrollSpeed
    #expect(scroll.keyTimes.count == 5)
    #expect(scroll.keyTimes.first == 0)
    #expect(scroll.keyTimes.last == 1)
    #expect(scroll.keyTimes == scroll.keyTimes.sorted())
    #expect(abs(scroll.keyTimes[1] * scroll.duration - wait) < 0.0001)
    #expect(abs(scroll.keyTimes[2] * scroll.duration - (wait + moves)) < 0.0001)
    #expect(abs(scroll.keyTimes[3] * scroll.duration - (wait + moves + NotchMotion.titleScrollHold)) < 0.0001)
    #expect(abs(scroll.duration - (wait + moves + NotchMotion.titleScrollHold + NotchMotion.titleScrollSnap)) < 0.0001)
}
