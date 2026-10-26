import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)

private func track(_ app: String, playing: Bool = true) -> PlaybackState {
    PlaybackState(bundleIdentifier: app, title: "Song from \(app)", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: playing ? 1 : 0)
}

private struct Run {
    var state = AppState()
    var effects: [AppEffect] = []
    var now = start

    init() {
        send(.housingsChanged([notch]))
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 1) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    mutating func report(_ app: String, _ playback: PlaybackState?) {
        send(.sourceReported(bundleIdentifier: app, playback))
    }

    var chips: [String] { state.chips.map(\.bundleIdentifier) }
}

@Test func twoAppsPlayingGiveTwoChipsAndOneGivesNone() {
    var run = Run()
    run.report("a", track("a"))
    #expect(run.chips == [])
    run.report("b", track("b"))
    #expect(run.chips == ["b", "a"])
    #expect(run.state.chips.map(\.isFollowed) == [true, false])
}

@Test func aPausedAppGetsNoChip() {
    var run = Run()
    run.report("a", track("a"))
    run.report("b", track("b", playing: false))
    #expect(run.chips == [])
    #expect(run.state.playback?.bundleIdentifier == "a")
}

@Test func aChipFollowsItsAppUntilThatAppStops() {
    var run = Run()
    run.report("a", track("a"))
    run.report("b", track("b"))
    run.send(.followSource("a"))
    #expect(run.state.playback?.bundleIdentifier == "a")
    run.report("b", track("b"))
    #expect(run.state.playback?.bundleIdentifier == "a")
    run.report("a", track("a", playing: false))
    #expect(run.state.sources.pinned == nil)
    #expect(run.state.playback?.bundleIdentifier == "b")
}

@Test func followingNilLetsThePriorityListDecideAgain() {
    var run = Run()
    run.report("a", track("a"))
    run.report("b", track("b"))
    run.send(.followSource("a"))
    run.send(.followSource(nil))
    #expect(run.state.playback?.bundleIdentifier == "b")
}

@Test func anAppThatWasNeverSeenIsNotFollowed() {
    var run = Run()
    run.report("a", track("a"))
    run.send(.followSource("nobody"))
    #expect(run.state.sources.pinned == nil)
    #expect(run.state.playback?.bundleIdentifier == "a")
}

@Test func anIgnoredAppIsNeverFollowed() {
    var run = Run()
    run.report("us.zoom.xos", track("us.zoom.xos"))
    #expect(run.state.playback == nil)
    run.report("a", track("a"))
    run.report("us.zoom.xos", track("us.zoom.xos"))
    #expect(run.state.playback?.bundleIdentifier == "a")
    #expect(run.chips == [])
    run.send(.followSource("us.zoom.xos"))
    #expect(run.state.playback?.bundleIdentifier == "a")
}

@Test func nothingFromOneAppLeavesTheOtherPlayingWithNoHide() {
    var run = Run()
    run.report("a", track("a"))
    run.report("b", track("b"))
    run.report("b", nil)
    #expect(run.state.playback?.bundleIdentifier == "a")
    #expect(run.state.hideAt == nil)
}

@Test func nothingFromTheLastAppHidesAfterTheDelay() {
    var run = Run()
    run.report("a", track("a"))
    run.report("a", nil)
    #expect(run.state.playback != nil)
    #expect(run.state.hideAt == run.now + AppState.hideDelay)
}

@Test func commandsLeaveOnlyThroughSend() {
    var run = Run()
    run.report("a", track("a"))
    run.report("b", track("b"))
    run.effects = []
    run.send(.followSource("a"))
    #expect(!run.effects.contains { if case .send = $0 { true } else { false } })
    run.send(.command(.togglePlayPause))
    #expect(run.effects.filter { if case .send = $0 { true } else { false } } == [.send(.togglePlayPause)])
}

@Test func withNothingPlayingThereIsNoDeadline() {
    var run = Run()
    run.report("a", track("a"))
    run.report("b", track("b"))
    run.report("a", nil)
    run.report("b", nil)
    run.send(.tick, after: AppState.hideDelay + 1)
    #expect(run.state.playback == nil)
    #expect(run.state.chips.isEmpty)
    #expect(run.state.deadline == nil)
}

private actor Single: NowPlayingSource {
    nonisolated let states: AsyncStream<PlaybackState?>
    private let continuation: AsyncStream<PlaybackState?>.Continuation
    init() { (states, continuation) = AsyncStream.makeStream() }
    func yield(_ state: PlaybackState?) { continuation.yield(state) }
    func finish() { continuation.finish() }
    func send(_ command: PlaybackCommand) async {}
}

@Test func aSourceOfOnePlayerEndsTheEarlierAppsReportWhenAnotherTakesOver() async {
    let source = Single()
    var reports = source.reports.makeAsyncIterator()
    await source.yield(track("a"))
    #expect(await reports.next()?.bundleIdentifier == "a")
    await source.yield(track("b"))
    #expect(await reports.next() == SourceReport(bundleIdentifier: "a", state: nil))
    #expect(await reports.next()?.bundleIdentifier == "b")
    await source.yield(nil)
    #expect(await reports.next() == SourceReport(bundleIdentifier: "b", state: nil))
    await source.finish()
    #expect(await reports.next() == nil)
}

@Test func aSkipThroughAReportOfNothingStillShowsTheTrackToast() {
    var run = Run()
    run.send(.trackToastChanged(true))
    run.report("a", track("a"))
    run.report("a", nil)
    var next = track("a")
    next.title = "Next song"
    run.report("a", next)
    #expect(run.state.toasts.current?.content.title == "Next song")
}
