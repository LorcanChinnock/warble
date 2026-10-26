import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)

/// Both notches with `song` playing, and the effects of everything after it.
private struct Run {
    var state = AppState()
    var effects: [AppEffect] = []
    var now = start

    init() {
        send(.housingsChanged([builtIn, external]))
        send(.playbackReported(song))
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    mutating func wait(_ seconds: TimeInterval) {
        let end = now + seconds
        while let due = state.deadline, due <= end {
            now = due
            effects += reduce(&state, .tick, now: due)
        }
        now = end
    }
}

@Test func aFullScreenAppHidesTheNotchOnItsDisplayOnly() {
    var run = Run()
    run.send(.fullScreenChanged(["built-in"]))
    #expect(run.state.notchState("built-in") == .hidden)
    #expect(run.state.notchState("external") == .resting)
}

@Test func aNotchOnAFullScreenDisplayIgnoresThePointer() {
    var run = Run()
    run.send(.fullScreenChanged(["built-in"]))
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.hover(display: "built-in", .click))
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("built-in") == .hidden)
    #expect(run.state.surfaces["built-in"]?.pointerInside == false)
    #expect(!run.state.hovering)
}

@Test func goingFullScreenClosesAnOpenCard() {
    var run = Run()
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.notchState("built-in") == .expanded)
    run.send(.fullScreenChanged(["built-in"]))
    #expect(run.state.notchState("built-in") == .hidden)
    #expect(run.effects.contains(.watchClicksOutside(false)))
    run.send(.fullScreenChanged([]))
    #expect(run.state.notchState("built-in") == .resting)
}

@Test func leavingFullScreenDrawsTheNotchAgain() {
    var run = Run()
    run.send(.fullScreenChanged(["built-in", "external"]))
    run.send(.fullScreenChanged(["external"]))
    #expect(run.state.notchState("built-in") == .resting)
    #expect(run.state.notchState("external") == .hidden)
}

@Test func aHousingThatArrivesOnAFullScreenDisplayStartsHidden() {
    var run = Run()
    run.send(.fullScreenChanged(["external"]))
    run.send(.housingsChanged([builtIn]))
    run.send(.housingsChanged([builtIn, external]))
    #expect(run.state.notchState("external") == .hidden)
}

