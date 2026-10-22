import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)
private let next = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Next", artist: "Artist", elapsedTimestamp: start, rate: 1)

/// Both notches with `song` playing, the built-in display showing a full-screen app, and the settings as given.
private struct Run {
    var state: AppState
    var now = start

    init(showsTrackToast: Bool = true, toastsInFullScreen: Bool = true) {
        state = AppState(showsTrackToast: showsTrackToast, toastsInFullScreen: toastsInFullScreen)
        send(.housingsChanged([builtIn, external]))
        send(.playbackReported(song))
        send(.fullScreenChanged(["built-in"]))
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        _ = reduce(&state, action, now: now)
    }

    mutating func wait(_ seconds: TimeInterval) {
        let end = now + seconds
        while let due = state.deadline, due <= end {
            now = due
            _ = reduce(&state, .tick, now: due)
        }
        now = end
    }

    var fullScreen: NotchState? { state.notchState("built-in") }
}

@Test func overAFullScreenAppOnlyTheToastShows() {
    var run = Run()
    #expect(run.fullScreen == .hidden)
    run.send(.playbackReported(next), after: 1)
    #expect(run.fullScreen == .toast)
    #expect(run.state.notchState("external") == .toast)
}

@Test func theToastGoesFromAFullScreenAppAndTheNotchStaysHidden() {
    var run = Run()
    run.send(.playbackReported(next), after: 1)
    run.wait(TrackToast.duration)
    #expect(run.fullScreen == .hidden)
    #expect(run.state.notchState("external") == .resting)
    #expect(run.state.deadline == nil)
}

@Test func withTheSettingOffAFullScreenAppShowsNoToast() {
    var run = Run(toastsInFullScreen: false)
    run.send(.playbackReported(next), after: 1)
    #expect(run.fullScreen == .hidden)
    #expect(run.state.notchState("external") == .toast)
}

@Test func withTheToastOffAFullScreenAppShowsNone() {
    var run = Run(showsTrackToast: false)
    run.send(.playbackReported(next), after: 1)
    #expect(run.fullScreen == .hidden)
}

@Test func turningTheSettingOffHidesAToastOverAFullScreenApp() {
    var run = Run()
    run.send(.playbackReported(next), after: 1)
    run.send(.toastsInFullScreenChanged(false))
    #expect(run.fullScreen == .hidden)
    #expect(run.state.notchState("external") == .toast)
    run.send(.toastsInFullScreenChanged(true))
    #expect(run.fullScreen == .toast)
}

@Test func aToastOverAFullScreenAppDoesntOpenTheCard() {
    var run = Run()
    run.send(.playbackReported(next), after: 1)
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.hover(display: "built-in", .click))
    run.wait(HoverIntent.expandDelay)
    #expect(run.fullScreen == .toast)
    #expect(run.state.surfaces["built-in"]?.pointerInside == false)
}
