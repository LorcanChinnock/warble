import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)

/// A notch with the waveform on, and the effects of everything after it.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(waveform: Bool = true) {
        state = AppState(showsWaveform: waveform)
        send(.housingsChanged([builtIn]))
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

    var captures: [Bool] {
        effects.compactMap { if case .captureAudio(let on) = $0 { on } else { nil } }
    }
}

@Test func theWaveformStartsOff() {
    #expect(!AppState().showsWaveform)
}

@Test func theTapStartsOnceWhenTheBarsAppearWhilePlaying() {
    var run = Run()
    run.send(.playbackReported(song))
    #expect(run.captures == [true])
    #expect(run.state.capturesAudio)
    run.send(.tick)
    run.send(.playbackReported(song))
    #expect(run.captures == [true])
}

@Test func theTapStopsOnAPause() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.command(.pause))
    #expect(run.captures == [true, false])
}

@Test func theTapStopsWhenTheNotchGoesIdle() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.playbackReported(nil))
    run.wait(AppState.hideDelay + 1)
    #expect(run.state.notchState("built-in") == .idle || run.state.notchState("built-in") == .hidden)
    #expect(run.captures == [true, false])
}

@Test func theTapStopsWhileACardIsOpenAndStartsAgainWhenItCloses() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.notchState("built-in") == .expanded)
    #expect(run.captures == [true, false])
    run.send(.dismiss(except: nil))
    #expect(run.captures == [true, false, true])
}

@Test func theTapStopsOverAFullScreenApp() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.fullScreenChanged(["built-in"]))
    #expect(run.captures == [true, false])
}

@Test func theTapStopsWhenTheSettingGoesOff() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.waveformChanged(false))
    #expect(run.captures == [true, false])
    #expect(!run.state.showsWaveform)
}

@Test func turningTheSettingOnWhilePlayingStartsTheTap() {
    var run = Run(waveform: false)
    run.send(.playbackReported(song))
    #expect(run.captures.isEmpty)
    run.send(.waveformChanged(true))
    #expect(run.captures == [true])
}

@Test func withTheSettingOffTheTapIsNeverAsked() {
    var run = Run(waveform: false)
    run.send(.playbackReported(song))
    run.send(.hover(display: "built-in", .click))
    run.send(.dismiss(except: nil))
    run.send(.command(.pause))
    run.send(.waveformChanged(false))
    #expect(run.captures.isEmpty)
}

@Test func aFailedTapTurnsTheWaveformOffAndLetsGo() {
    var run = Run()
    run.send(.playbackReported(song))
    run.send(.audioCaptureDenied)
    #expect(!run.state.showsWaveform)
    #expect(run.effects.contains(.turnOffWaveform))
    #expect(run.captures == [true, false])
    // Turning it on again tries again.
    run.send(.waveformChanged(true))
    #expect(run.captures == [true, false, true])
}

@Test func withNothingPlayingThereIsNoTapAndNoDeadline() {
    var run = Run()
    run.send(.waveformChanged(true))
    run.send(.tick)
    #expect(run.captures.isEmpty)
    #expect(run.state.deadline == nil)
}

// MARK: Runner

@MainActor
@Test func theRunnerStartsAndStopsTheTapAndPassesFramesOn() {
    let tap = FakeAudioTap()
    let runner = makeRunner(audioTap: tap)
    let box = FrameBox()
    runner.spectrum = { box.append($0) }
    runner.perform(.captureAudio(true))
    #expect(tap.isRunning)
    tap.emit([0.1, 0.2, 0.3, 0.4])
    #expect(box.frames == [[0.1, 0.2, 0.3, 0.4]])
    runner.perform(.captureAudio(false))
    #expect(!tap.isRunning)
    #expect(tap.stops == 1)
    tap.emit([1, 1, 1, 1])
    #expect(box.frames.count == 1)
}

@MainActor
@Test func aFailureOfTheTapIsReportedOnce() async {
    let tap = FakeAudioTap()
    let runner = makeRunner(audioTap: tap)
    let actions = ActionBox()
    runner.dispatch = { actions.append($0) }
    runner.perform(.captureAudio(true))
    tap.fail()
    await Task.yield()
    await Task.yield()
    #expect(actions.actions == [.audioCaptureDenied])
}

@MainActor
@Test func aFailureOfAStoppedTapIsIgnored() async {
    let tap = FakeAudioTap()
    let runner = makeRunner(audioTap: tap)
    let actions = ActionBox()
    runner.dispatch = { actions.append($0) }
    runner.perform(.captureAudio(true))
    runner.perform(.captureAudio(false))
    // macOS reports the first start's failure after it was stopped, as the real tap can.
    tap.failEarlier()
    await Task.yield()
    await Task.yield()
    #expect(actions.actions.isEmpty)
    runner.perform(.captureAudio(true))
    tap.fail()
    await Task.yield()
    await Task.yield()
    #expect(actions.actions == [.audioCaptureDenied])
}

@MainActor
@Test func withoutATapTheRunnerDoesNothing() {
    let runner = makeRunner()
    runner.perform(.captureAudio(true))
    runner.perform(.captureAudio(false))
}

private final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _frames: [[Float]] = []
    var frames: [[Float]] { lock.withLock { _frames } }
    func append(_ frame: [Float]) { lock.withLock { _frames.append(frame) } }
}

@MainActor
private final class ActionBox {
    var actions: [AppAction] = []
    func append(_ action: AppAction) { actions.append(action) }
}
