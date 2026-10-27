import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: 1, shuffle: .off, repeatMode: .off)
private let airPods: UInt32 = 1
private let speakers: UInt32 = 2

/// A player's card open over AirPods, with the speakers on offer.
private struct Run {
    var state = AppState()
    var now = start

    init() {
        send(.housingsChanged([notch]))
        send(.playbackReported(song))
        send(.hover(display: "built-in", .click))
        send(.outputsRead([], current: airPods))
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        _ = reduce(&state, action, now: now)
    }
}

@Test func anOutputThatComesBackRightAfterASwitchIsExplained() {
    var run = Run()
    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: speakers))
    #expect(run.state.outputSwitch.kept == nil)
    run.send(.outputsRead([], current: airPods), after: 0.06)
    #expect(run.state.outputSwitch.kept == airPods)
}

@Test func aSwitchThatSticksSaysNothing() {
    var run = Run()
    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: speakers))
    run.send(.tick, after: OutputSwitch.watchWindow)
    run.send(.outputsRead([], current: airPods), after: 30)
    #expect(run.state.outputSwitch.kept == nil)
}

@Test func anOutputThatChangesLongAfterASwitchIsNotOurs() {
    var run = Run()
    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: speakers))
    run.send(.outputsRead([], current: airPods), after: OutputSwitch.watchWindow + 0.1)
    #expect(run.state.outputSwitch.kept == nil)
}

@Test func aThirdOutputEndsTheWatch() {
    var run = Run()
    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: 3))
    run.send(.outputsRead([], current: airPods), after: 0.1)
    #expect(run.state.outputSwitch.kept == nil)
}

@Test func theNoteGoesAfterItsTimeAndAnotherSwitchClearsIt() {
    var run = Run()
    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: airPods), after: 0.06)
    #expect(run.state.deadline == run.now + OutputSwitch.noteDuration)
    run.send(.tick, after: OutputSwitch.noteDuration)
    #expect(run.state.outputSwitch.kept == nil)
    #expect(run.state.deadline == nil)

    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: airPods), after: 0.06)
    run.send(.selectOutput(speakers), after: 1)
    #expect(run.state.outputSwitch.kept == nil)
}

@Test func theWatchIsTheOnlyThingDueWhileItRuns() {
    var run = Run()
    #expect(run.state.deadline == nil)
    run.send(.selectOutput(speakers))
    #expect(run.state.deadline == run.now + OutputSwitch.watchWindow)
    run.send(.tick, after: OutputSwitch.watchWindow)
    #expect(run.state.deadline == nil)
}

@Test func theNoteOutlastsTheCardClosingUnderTheMenu() {
    var run = Run()
    run.send(.selectOutput(speakers))
    run.send(.outputsRead([], current: airPods), after: 0.06)
    run.send(.dismiss(except: nil))
    #expect(run.state.outputSwitch.kept == airPods)
    run.send(.tick, after: OutputSwitch.noteDuration)
    #expect(run.state.outputSwitch.kept == nil)
}

@Test func theCardStaysOpenForTheNoteWithThePointerAwayFromIt() {
    var run = Run()
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.menu(display: "built-in", open: true))
    run.send(.selectOutput(speakers))
    run.send(.pointer(display: "built-in", inside: false), after: 0.1)
    run.send(.menu(display: "built-in", open: false), after: 0.1)
    run.send(.outputsRead([], current: airPods), after: 0.06)
    run.send(.tick, after: HoverIntent.collapseDelay)
    #expect(run.state.notchState("built-in") == .expanded)
    run.send(.tick, after: OutputSwitch.holdDuration)
    #expect(run.state.notchState("built-in") == .resting)
}
