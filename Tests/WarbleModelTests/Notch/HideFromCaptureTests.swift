import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)

/// Both notches, with the setting as given and the effects of everything after them.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(hidesFromCapture: Bool = false) {
        state = AppState(hidesFromCapture: hidesFromCapture)
        send(.housingsChanged([builtIn, external]))
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

    var notches: [NotchState?] { [state.notchState("built-in"), state.notchState("external")] }
}

@Test func hidingFromCaptureStartsOff() {
    #expect(!AppState().hidesFromCapture)
}

@Test func turningHidingFromCaptureOnAndOffFollowsSettings() {
    var run = Run()
    run.send(.hidesFromCaptureChanged(true))
    #expect(run.state.hidesFromCapture)
    run.send(.hidesFromCaptureChanged(false))
    #expect(!run.state.hidesFromCapture)
}

@Test func hidingFromCaptureWatchesNothingAndSetsNoTimer() {
    var run = Run()
    run.send(.hidesFromCaptureChanged(true))
    #expect(run.effects.isEmpty)
    #expect(run.state.deadline == nil)
    #expect(run.notches == [.idle, .idle])
}

/// A song playing, then a hover that opens the built-in notch, with the notches' states after each.
private func playAndHover(hidesFromCapture: Bool) -> (run: Run, playing: [NotchState?], hovered: [NotchState?]) {
    var run = Run(hidesFromCapture: hidesFromCapture)
    run.send(.playbackReported(song))
    let playing = run.notches
    run.send(.pointer(display: "built-in", inside: true), after: 1)
    run.wait(HoverIntent.expandDelay)
    return (run, playing, run.notches)
}

@Test func hidingFromCaptureLeavesWhatYouSeeAlone() {
    let on = playAndHover(hidesFromCapture: true)
    let off = playAndHover(hidesFromCapture: false)
    #expect(on.playing == [.resting, .resting])
    #expect(on.hovered == [.expanded, .resting])
    #expect(on.playing == off.playing)
    #expect(on.hovered == off.hovered)
    #expect(on.run.effects == off.run.effects)
}

@Test func turningHidingFromCaptureOnLeavesAnOpenCardOpen() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.hover(display: "built-in", .click))
    run.effects = []
    run.send(.hidesFromCaptureChanged(true))
    #expect(run.state.notchState("built-in") == .expanded)
    #expect(run.effects.isEmpty)
}
