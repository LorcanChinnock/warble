import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)

private func track(_ title: String, artist: String = "Artist", rate: Double = 1) -> PlaybackState {
    PlaybackState(bundleIdentifier: "com.apple.Music", title: title, artist: artist, duration: 300, elapsedTimestamp: start, rate: rate)
}

/// A notch with stats on, and the effects of everything after it.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(stats: Bool = true) {
        state = AppState(keepsStats: stats)
        send(.housingsChanged([builtIn]))
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    var recorded: [ListenedSpan] {
        effects.compactMap { if case .recordListening(let span) = $0 { span } else { nil } }
    }
}

@Test func statsStartOff() {
    #expect(!AppState().keepsStats)
}

@Test func aTrackPlayedThenPausedRecordsOneSpanOfThatLength() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    run.send(.playbackReported(track("Song", rate: 0)), after: 90)
    #expect(run.recorded == [ListenedSpan(start: start, seconds: 90, title: "Song", artist: "Artist")])
}

@Test func timeSpentPausedIsNotCounted() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    run.send(.playbackReported(track("Song", rate: 0)), after: 30)
    run.send(.playbackReported(track("Song")), after: 600)
    run.send(.playbackReported(track("Song", rate: 0)), after: 20)
    #expect(run.recorded.map(\.seconds) == [30, 20])
}

@Test func aSeekDoesNotChangeTheSpan() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    var seeked = track("Song")
    seeked.elapsed = 200
    run.send(.playbackReported(seeked), after: 40)
    #expect(run.recorded.isEmpty)
    run.send(.playbackReported(track("Song", rate: 0)), after: 20)
    #expect(run.recorded.map(\.seconds) == [60])
}

@Test func aTrackChangeEndsOneSpanAndStartsTheNext() {
    var run = Run()
    run.send(.playbackReported(track("One")))
    run.send(.playbackReported(track("Two")), after: 100)
    run.send(.playbackReported(track("Two", rate: 0)), after: 50)
    #expect(run.recorded.map(\.title) == ["One", "Two"])
    #expect(run.recorded.map(\.seconds) == [100, 50])
    #expect(run.recorded[1].start == start + 100)
}

@Test func theGapAfterAReportOfNothingIsNotCounted() {
    var run = Run()
    run.send(.playbackReported(track("One")))
    run.send(.playbackReported(nil), after: 60)
    run.send(.tick, after: AppState.hideDelay)
    #expect(run.recorded.map(\.seconds) == [60])
    run.send(.playbackReported(track("Two")), after: 10)
    #expect(run.state.stats.session?.since == run.now)
}

@Test func aPauseFromTheNotchIsCountedAtTheClick() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    run.send(.command(.pause), after: 45)
    #expect(run.recorded.map(\.seconds) == [45])
}

@Test func aSkipThroughTracksIsNotCounted() {
    var run = Run()
    run.send(.playbackReported(track("One")))
    run.send(.playbackReported(track("Two")), after: 0.4)
    run.send(.playbackReported(track("Three")), after: 0.4)
    run.send(.playbackReported(track("Three", rate: 0)), after: 5)
    #expect(run.recorded.map(\.title) == ["Three"])
}

@Test func withStatsOffNothingIsRecorded() {
    var run = Run(stats: false)
    run.send(.playbackReported(track("Song")))
    run.send(.playbackReported(track("Song", rate: 0)), after: 90)
    run.send(.willQuit)
    #expect(run.recorded.isEmpty)
    #expect(run.state.stats.session == nil)
}

@Test func turningStatsOffDropsTheTrackUnderWayUnwritten() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    run.send(.statsChanged(false), after: 90)
    run.send(.playbackReported(track("Song", rate: 0)), after: 90)
    #expect(run.recorded.isEmpty)
}

@Test func turningStatsOnWhilePlayingCountsFromThen() {
    var run = Run(stats: false)
    run.send(.playbackReported(track("Song")))
    run.send(.statsChanged(true), after: 500)
    run.send(.playbackReported(track("Song", rate: 0)), after: 30)
    #expect(run.recorded.map(\.seconds) == [30])
}

@Test func quittingRecordsTheTrackUnderWayOnce() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    run.send(.willQuit, after: 75)
    #expect(run.recorded.map(\.seconds) == [75])
    run.send(.tick, after: 10)
    #expect(run.recorded.count == 1)
    #expect(run.state.stats.session == nil)
}

@Test func clearingEmptiesTheSummaryAndCountsTheTrackUnderWayFromThen() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    run.send(.statsLoaded([ListenedSpan(start: start, seconds: 100, title: "Old", artist: "A")]), after: 10)
    #expect(run.state.weeklySummary?.totalSeconds == 100)
    run.send(.clearStats, after: 20)
    #expect(run.state.weeklySummary?.isEmpty == true)
    #expect(run.effects.contains(.clearStats))
    run.send(.playbackReported(track("Song", rate: 0)), after: 30)
    #expect(run.recorded.map(\.seconds) == [30])
}

@Test func refreshingAsksForTheLastThirtyDays() {
    var run = Run()
    run.send(.refreshStats)
    #expect(run.effects == [.loadStats(since: start - WeeklySummary.retention)])
}

@Test func nothingPlayingMeansNoDeadline() {
    var run = Run()
    #expect(run.state.deadline == nil)
    run.send(.playbackReported(track("Song")))
    run.send(.playbackReported(track("Song", rate: 0)), after: 10)
    run.send(.statsLoaded([]))
    #expect(run.state.stats.deadline == nil)
}

@Test func playingWithStatsOnAddsNoDeadline() {
    var run = Run()
    run.send(.playbackReported(track("Song")))
    #expect(run.state.stats.deadline == nil)
}
