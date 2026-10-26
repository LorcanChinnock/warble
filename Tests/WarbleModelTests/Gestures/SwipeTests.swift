import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let song = PlaybackState(
    bundleIdentifier: "com.apple.Music", title: "Hey Jude", artist: "The Beatles", duration: 431, elapsed: 0,
    elapsedTimestamp: start, rate: 1
)

/// A notch with swipe to skip on and `song` playing, unless told otherwise, and the effects of everything after.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(swipeToSkip: Bool = true, playing: PlaybackState? = song) {
        state = AppState(swipeToSkip: swipeToSkip)
        send(.housingsChanged([builtIn]))
        if let playing {
            send(.sourceReported(bundleIdentifier: "app", playing))
        }
        effects = []
    }

    mutating func send(_ action: AppAction) {
        now += 0.01
        effects += reduce(&state, action, now: now)
    }

    /// A trackpad gesture: the fingers touch, move by each of `steps`, lift, then coast by each of `momentum`.
    mutating func gesture(
        _ steps: [(across: Double, down: Double)], momentum: [(across: Double, down: Double)] = [], inverted: Bool = false
    ) {
        scroll(0, 0, .began, inverted: inverted)
        for step in steps {
            scroll(step.across, step.down, .changed, inverted: inverted)
        }
        scroll(0, 0, .ended, inverted: inverted)
        for step in momentum {
            scroll(step.across, step.down, .momentum, inverted: inverted)
        }
    }

    mutating func scroll(_ across: Double, _ down: Double, _ phase: Swipe.Phase?, inverted: Bool = false) {
        send(.scrolled(delta: down, across: across, phase: phase, precise: true, inverted: inverted, volume: 0.5, isMuted: false))
    }

    var sent: [PlaybackCommand] {
        effects.compactMap { if case .send(let command) = $0 { command } else { nil } }
    }

    var volumeSet: Bool {
        effects.contains { if case .setVolume = $0 { true } else { false } }
    }
}

private let left = Array(repeating: (across: 10.0, down: 1.0), count: 8)
private let right = left.map { (across: -$0.across, down: $0.down) }

@Test func withTheSettingOffASwipeSendsNothing() {
    var run = Run(swipeToSkip: false)
    run.gesture(left)
    #expect(run.sent.isEmpty)
}

@Test func aSwipeLeftSkipsForwardOnceWithATick() {
    var run = Run()
    run.gesture(left)
    #expect(run.sent == [.nextTrack])
    #expect(run.effects.filter { $0 == .haptic }.count == 1)
}

@Test func aSwipeRightGoesBack() {
    var run = Run()
    run.gesture(right)
    #expect(run.sent == [.previousTrack])
}

@Test func naturalScrollingFlipsTheDeltaSoTheFingersStillDecide() {
    // With natural scrolling, fingers moving left report a negative delta.
    var run = Run()
    run.gesture(right, inverted: true)
    #expect(run.sent == [.nextTrack])
    run.effects = []
    run.gesture(left, inverted: true)
    #expect(run.sent == [.previousTrack])
}

@Test func aSwipeThatKeepsGoingSkipsOnceUntilANewOneBegins() {
    var run = Run()
    run.gesture(left + left + left, momentum: left)
    #expect(run.sent == [.nextTrack])
    run.gesture(left)
    #expect(run.sent == [.nextTrack, .nextTrack])
}

@Test func aShortSwipeDoesNotSkip() {
    var run = Run()
    run.gesture([(across: 10, down: 0), (across: 10, down: 0)])
    #expect(run.sent.isEmpty)
    #expect(Swipe.skipDistance > 20)
}

@Test func aSwipeLeavesTheVolumeAlone() {
    var run = Run()
    run.gesture(left, momentum: left)
    #expect(!run.volumeSet)
}

@Test func aMostlyVerticalScrollChangesTheVolumeAndDoesNotSkip() {
    var run = Run()
    run.gesture(Array(repeating: (across: 6, down: 10), count: 20), momentum: [(across: 6, down: 10)])
    #expect(run.sent.isEmpty)
    #expect(run.volumeSet)
}

@Test func aScrollHeldBackWhileItsWayIsDecidedStillCounts() {
    var run = Run()
    run.scroll(0, 0, .began)
    run.scroll(0, 4, .changed)
    #expect(run.effects.isEmpty)
    run.scroll(0, 4, .changed)
    #expect(run.effects.first == .setVolume(VolumeScroll.volume(after: 8, from: 0.5, precise: true, inverted: false)))
}

@Test func aMouseWheelOnlyScrollsEvenSideways() {
    var run = Run()
    for _ in 0..<10 {
        run.send(.scrolled(delta: 1, across: 20, phase: nil, precise: false, inverted: false, volume: 0.5, isMuted: false))
    }
    #expect(run.sent.isEmpty)
    #expect(run.volumeSet)
}

@Test func withTheSettingOffATrackpadScrollChangesTheVolumeAsBefore() {
    var run = Run(swipeToSkip: false)
    run.scroll(0, 2, .changed)
    #expect(run.effects == [.setVolume(VolumeScroll.volume(after: 2, from: 0.5, precise: true, inverted: false))])
}

@Test func withNothingPlayingASwipeSendsNothingAndThereIsNoDeadline() {
    var run = Run(playing: nil)
    run.gesture(left)
    #expect(run.effects.isEmpty)
    #expect(run.state.deadline == nil)
}

@Test func turningItOnInSettingsMakesASwipeSkip() {
    var run = Run(swipeToSkip: false)
    run.send(.swipeToSkipChanged(true))
    run.gesture(left)
    #expect(run.sent == [.nextTrack])
}
