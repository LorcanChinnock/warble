import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func span(_ title: String, daysAgo: Double = 0) -> ListenedSpan {
    ListenedSpan(start: start - daysAgo * 86400, seconds: 60, title: title, artist: "Artist")
}

@MainActor
@Test func spansAreWrittenInTheOrderTheyWereAskedFor() async {
    let stats = FakeStats()
    let runner = makeRunner(stats: stats)
    let first = span("One"), second = span("Two"), third = span("Three")
    for item in [first, second, third] {
        runner.perform(.recordListening(item))
    }
    await runner.finish()
    #expect(stats.saved == [first, second, third])
}

@MainActor
@Test func loadingWaitsForTheWritesBeforeIt() async {
    let stats = FakeStats()
    let runner = makeRunner(stats: stats)
    var answers: [AppAction] = []
    runner.dispatch = { answers.append($0) }
    runner.perform(.recordListening(span("One")))
    runner.perform(.loadStats(since: start - 30 * 86400))
    await runner.finish()
    #expect(answers == [.statsLoaded([span("One")])])
}

@MainActor
@Test func loadingLeavesOutSpansBeforeTheDate() async {
    let stats = FakeStats()
    let runner = makeRunner(stats: stats)
    var answers: [AppAction] = []
    runner.dispatch = { answers.append($0) }
    runner.perform(.recordListening(span("Old", daysAgo: 40)))
    runner.perform(.recordListening(span("New", daysAgo: 1)))
    runner.perform(.loadStats(since: start - 30 * 86400))
    await runner.finish()
    #expect(answers == [.statsLoaded([span("New", daysAgo: 1)])])
}

@MainActor
@Test func clearingEmptiesTheStore() async {
    let stats = FakeStats()
    let runner = makeRunner(stats: stats)
    runner.perform(.recordListening(span("One")))
    runner.perform(.clearStats)
    await runner.finish()
    #expect(stats.saved.isEmpty)
}

@MainActor
@Test func flushingWaitsForTheWriteUnderWay() {
    let stats = FakeStats()
    let runner = makeRunner(stats: stats)
    runner.perform(.recordListening(span("One")))
    runner.flushStats()
    #expect(stats.saved == [span("One")])
}
