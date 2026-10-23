import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: start, rate: 1)

@Test func theCommandLineStartsOff() {
    #expect(!AppState().listensForCommands)
}

@Test func aLaunchWithTheCommandLineOffAsksForNothing() {
    var state = AppState()
    #expect(reduce(&state, .launched(firstRun: false), now: start).isEmpty)
    #expect(!reduce(&state, .playbackReported(song), now: start).contains(.listenForCommands(false)))
    #expect(reduce(&state, .commandLineChanged(false), now: start).isEmpty)
}

@Test func turningTheCommandLineOnAsksForTheSocketOnce() {
    var state = AppState()
    #expect(reduce(&state, .commandLineChanged(true), now: start) == [.listenForCommands(true)])
    #expect(state.listensForCommands)
    // Other changes and the same setting again ask for nothing more.
    #expect(reduce(&state, .commandLineChanged(true), now: start).isEmpty)
    #expect(!reduce(&state, .playbackReported(song), now: start).contains(.listenForCommands(true)))
    #expect(reduce(&state, .tick, now: start + 1).isEmpty)
}

@Test func turningTheCommandLineOffClosesTheSocketOnce() {
    var state = AppState()
    _ = reduce(&state, .commandLineChanged(true), now: start)
    #expect(reduce(&state, .commandLineChanged(false), now: start) == [.listenForCommands(false)])
    #expect(reduce(&state, .commandLineChanged(false), now: start).isEmpty)
    #expect(!state.listening)
}

@Test func aLaunchWithTheCommandLineOnOpensTheSocketAtTheFirstAction() {
    var state = AppState(listensForCommands: true)
    #expect(reduce(&state, .launched(firstRun: false), now: start) == [.listenForCommands(true)])
    #expect(reduce(&state, .tick, now: start).isEmpty)
}

@Test func theCommandLineAndLinksAreSeparateSettings() {
    var state = AppState()
    _ = reduce(&state, .commandLineChanged(true), now: start)
    #expect(!state.answersLinks)
    _ = reduce(&state, .linksChanged(true), now: start)
    _ = reduce(&state, .commandLineChanged(false), now: start)
    #expect(state.answersLinks)
}

@Test func theCommandLineSetsNoTimerOfItsOwn() {
    var state = AppState(listensForCommands: true)
    _ = reduce(&state, .launched(firstRun: false), now: start)
    #expect(state.deadline == nil)
}
