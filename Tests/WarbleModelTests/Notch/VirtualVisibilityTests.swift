import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)
private let paused = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 0)

private struct Run {
    var state = AppState()
    var now = start

    init(_ housings: [NotchHousing], _ visibility: VirtualNotchVisibility = .standard) {
        send(.housingsChanged(housings))
        send(.virtualVisibilityChanged(visibility))
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        _ = reduce(&state, action, now: now)
    }
}

@Test func aVirtualNotchIsThereOnlyWhenPlayingAtFirst() {
    var run = Run([external])
    #expect(run.state.notches.virtualVisibility == .whenPlaying)
    #expect(run.state.notchState("external") == .hidden)
    run.send(.playbackReported(song))
    #expect(run.state.notchState("external") == .resting)
    run.send(.playbackReported(paused), after: 1)
    run.send(.tick, after: IdleAfterPause.delay + 1)
    #expect(run.state.notchState("external") == .hidden)
}

@Test func anAlwaysVirtualNotchStaysEmptyAfterIdle() {
    var run = Run([external], .always)
    #expect(run.state.notchState("external") == .empty)
    run.send(.playbackReported(song))
    #expect(run.state.notchState("external") == .resting)
    run.send(.playbackReported(paused), after: 1)
    run.send(.tick, after: IdleAfterPause.delay + 1)
    #expect(run.state.notchState("external") == .empty)
    #expect(run.state.deadline == nil)
}

@Test func anOffVirtualNotchDrawsNothingEvenWhilePlaying() {
    var run = Run([external], .off)
    run.send(.playbackReported(song))
    #expect(run.state.notchState("external") == .hidden)
    #expect(!run.state.titleInNotch("external"))
}

@Test func theChoiceChangesTheNotchAtOnce() {
    var run = Run([external])
    run.send(.playbackReported(song))
    run.send(.virtualVisibilityChanged(.off))
    #expect(run.state.notchState("external") == .hidden)
    run.send(.virtualVisibilityChanged(.always))
    #expect(run.state.notchState("external") == .resting)
}

@Test func anOpenVirtualNotchClosesWhenItIsTurnedOff() {
    var run = Run([external])
    run.send(.playbackReported(song))
    run.send(.pointer(display: "external", inside: true))
    run.send(.tick, after: HoverIntent.expandDelay)
    #expect(run.state.notchState("external") == .expanded)
    run.send(.virtualVisibilityChanged(.off))
    #expect(run.state.notchState("external") == .hidden)
    #expect(!run.state.hovering)
    run.send(.virtualVisibilityChanged(.whenPlaying))
    #expect(run.state.notchState("external") == .resting)
}

@Test func aRealNotchIgnoresTheChoice() {
    for visibility in VirtualNotchVisibility.allCases {
        var run = Run([builtIn], visibility)
        #expect(run.state.notchState("built-in") == .empty)
        run.send(.playbackReported(song))
        #expect(run.state.notchState("built-in") == .resting)
    }
}

@Test func anEmptyNotchIsTheHousingAndTakesHoverThere() {
    let notch = external.frame
    #expect(NotchLayout.frame(.empty, notch: notch) == notch)
    #expect(NotchLayout.hoverArea(.empty, notch: notch) == notch)
}

@Test func fullScreenHidesAnEmptyNotch() {
    var run = Run([external], .always)
    run.send(.fullScreenChanged(["external"]))
    #expect(run.state.notchState("external") == .hidden)
}
