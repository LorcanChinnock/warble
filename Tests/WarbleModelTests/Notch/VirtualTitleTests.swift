import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)
private let next = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Next", artist: "Artist", elapsedTimestamp: start, rate: 1)

private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(showsVirtualTitle: Bool = true, showsTrackToast: Bool = false) {
        state = AppState(showsTrackToast: showsTrackToast, showsVirtualTitle: showsVirtualTitle)
        send(.housingsChanged([builtIn, external]))
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    var titles: [Bool] { [state.titleInNotch("built-in"), state.titleInNotch("external")] }
}

@Test func theVirtualTitleStartsOn() {
    #expect(AppState().showsVirtualTitle)
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

@Test func noTitleShowsWhileIdle() {
    var run = Run()
    #expect(run.titles == [false, false])
    run.send(.playbackReported(song))
    run.send(.playbackReported(nil), after: 1)
    run.send(.tick, after: AppState.hideDelay)
    #expect(run.state.notchState("external") == .idle)
    #expect(run.titles == [false, false])
}

@Test func theTitleAsksForNoEffectAndSetsNoTimerWithNothingPlaying() {
    var run = Run()
    run.send(.virtualTitleChanged(false))
    run.send(.virtualTitleChanged(true))
    #expect(run.effects.isEmpty)
    #expect(run.state.deadline == nil)
}

@Test func theTitleSaysWhatTheTrackChangeToastWould() {
    var run = Run(showsTrackToast: true)
    run.send(.playbackReported(song))
    run.send(.playbackReported(next), after: 1)
    #expect(run.state.toasts.current != nil)
    #expect(run.state.notchState("built-in") == .toast)
    #expect(run.state.notchState("external") == .resting)
}

@Test func withoutTheTitleAVirtualNotchShowsTheToastAsBefore() {
    var run = Run(showsVirtualTitle: false, showsTrackToast: true)
    run.send(.playbackReported(song))
    run.send(.playbackReported(next), after: 1)
    #expect(run.state.notchState("external") == .toast)
}

@Test func overAFullScreenAppTheTitleAndTheToastGo() {
    var run = Run(showsTrackToast: true)
    run.send(.playbackReported(song))
    run.send(.fullScreenChanged(["external"]))
    run.send(.playbackReported(next), after: 1)
    #expect(!run.state.titleInNotch("external"))
    #expect(run.state.notchState("external") == .hidden)
}

@Test func theTitleDoesNotChangeWhatAHoverOpens() {
    var on = Run()
    var off = Run(showsVirtualTitle: false)
    for index in 0..<2 {
        var run = index == 0 ? on : off
        run.send(.playbackReported(song))
        run.send(.hover(display: "external", .click))
        #expect(run.state.notchState("external") == .expanded)
        if index == 0 { on = run } else { off = run }
    }
    #expect(on.state.card("external") == off.state.card("external"))
}
