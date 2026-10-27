import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)
private let untitled = PlaybackState(bundleIdentifier: "com.apple.Music", title: "", artist: "Artist", elapsedTimestamp: start, rate: 1)

private struct Run {
    var state = AppState()
    var effects: [AppEffect] = []
    var now = start

    init(showsVirtualTitle: Bool = true) {
        send(.housingsChanged([builtIn, external]))
        if showsVirtualTitle {
            send(.virtualTitleChanged(true))
        }
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    var titles: [Bool] { [state.titleInNotch("built-in"), state.titleInNotch("external")] }
}

@Test func theVirtualTitleStartsOff() {
    #expect(!AppState().notches.showsVirtualTitle)
}

@Test func aVirtualNotchDrawsTheTitleWhilePlayingAndARealOneNever() {
    var run = Run()
    run.send(.playbackReported(song))
    #expect(run.titles == [false, true])
    #expect(run.state.notchState("external") == .resting)
}

@Test func theTitleFollowsSettings() {
    var run = Run(showsVirtualTitle: false)
    run.send(.playbackReported(song))
    #expect(run.titles == [false, false])
    run.send(.virtualTitleChanged(true))
    #expect(run.titles == [false, true])
    run.send(.virtualTitleChanged(false))
    #expect(run.titles == [false, false])
}

@Test func aPausedTrackKeepsItsTitleUntilIdle() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.playbackReported(PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 0)), after: 5)
    #expect(run.titles == [false, true])
    run.send(.tick, after: IdleAfterPause.delay)
    #expect(run.titles == [false, false])
}

@Test func nothingShowsWithNothingPlayingOrNoTitle() {
    var run = Run()
    #expect(run.titles == [false, false])
    run.send(.playbackReported(untitled))
    #expect(run.titles == [false, false])
}

@Test func nothingIsAskedForAndNoTimerIsSet() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.virtualTitleChanged(false))
    run.send(.virtualTitleChanged(true))
    #expect(run.effects.isEmpty)
    #expect(run.state.deadline == nil)
}

@Test func aFullScreenAppHidesTheTitleWithTheNotch() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.fullScreenChanged(["external"]))
    #expect(run.titles == [false, false])
    run.send(.fullScreenChanged([]))
    #expect(run.titles == [false, true])
}
