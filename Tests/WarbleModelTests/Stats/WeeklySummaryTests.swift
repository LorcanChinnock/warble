import Foundation
import Testing
@testable import WarbleModel

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let day: TimeInterval = 24 * 3600

private func span(_ title: String, _ artist: String?, _ seconds: TimeInterval, daysAgo: Double = 0) -> ListenedSpan {
    ListenedSpan(start: now - daysAgo * day, seconds: seconds, title: title, artist: artist)
}

@Test func spansOlderThanSevenDaysAreLeftOut() {
    let summary = WeeklySummary([span("New", "A", 100, daysAgo: 6.9), span("Old", "B", 500, daysAgo: 7.1)], at: now)
    #expect(summary.totalSeconds == 100)
    #expect(summary.topArtists.map(\.name) == ["A"])
    #expect(summary.topTracks.map(\.title) == ["New"])
}

@Test func timeAddsUpByArtistAndByTrack() {
    let summary = WeeklySummary([
        span("One", "A", 100), span("Two", "A", 50), span("One", "A", 30, daysAgo: 1), span("Three", "B", 120),
    ], at: now)
    #expect(summary.totalSeconds == 300)
    #expect(summary.topArtists == [.init(name: "A", seconds: 180), .init(name: "B", seconds: 120)])
    #expect(summary.topTracks.first == .init(title: "One", artist: "A", seconds: 130))
}

@Test func tiesAreOrderedByNameTheSameWayEveryTime() {
    let spans = [span("Zed", "Z", 60), span("Alpha", "A", 60), span("Mid", "M", 60)]
    for _ in 0..<5 {
        let summary = WeeklySummary(spans.shuffled(), at: now)
        #expect(summary.topArtists.map(\.name) == ["A", "M", "Z"])
        #expect(summary.topTracks.map(\.title) == ["Alpha", "Mid", "Zed"])
    }
}

@Test func onlyTheTopFiveAreListed() {
    let spans = (1...8).map { span("Track \($0)", "Artist \($0)", Double($0) * 10) }
    let summary = WeeklySummary(spans, at: now)
    #expect(summary.topArtists.count == 5)
    #expect(summary.topTracks.first?.title == "Track 8")
}

@Test func aTrackWithNoArtistCountsInTheTotalAndTheTracksOnly() {
    let summary = WeeklySummary([span("Episode", nil, 600)], at: now)
    #expect(summary.totalSeconds == 600)
    #expect(summary.topArtists.isEmpty)
    #expect(summary.topTracks.map(\.title) == ["Episode"])
}

@Test func olderHistoryStillCountsAsHistoryToClear() {
    let summary = WeeklySummary([span("Old", "A", 100, daysAgo: 20)], at: now)
    #expect(summary.isEmpty)
    #expect(summary.holdsHistory)
    #expect(!WeeklySummary([], at: now).holdsHistory)
    #expect(!WeeklySummary.empty.holdsHistory)
}

@Test func noSpansMakeAnEmptySummary() {
    #expect(WeeklySummary([], at: now).isEmpty)
    #expect(WeeklySummary.empty.isEmpty)
}
