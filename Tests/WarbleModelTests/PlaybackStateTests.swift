import Foundation
import Testing
@testable import WarbleModel

private let reported = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func track(elapsed: TimeInterval = 30, rate: Double, duration: TimeInterval? = 240) -> PlaybackState {
    PlaybackState(
        bundleIdentifier: "com.apple.Music", title: "Song", duration: duration,
        elapsed: elapsed, elapsedTimestamp: reported, rate: rate
    )
}

@Test func aPausedTrackStaysWhereItWasReported() {
    let state = track(rate: 0)
    #expect(!state.isPlaying)
    #expect(state.elapsed(at: reported) == 30)
    #expect(state.elapsed(at: reported + 90) == 30)
}

@Test func aPlayingTrackRunsOnInRealTime() {
    let state = track(rate: 1)
    #expect(state.isPlaying)
    #expect(state.elapsed(at: reported) == 30)
    #expect(state.elapsed(at: reported + 10) == 40)
    #expect(state.elapsed(at: reported + 0.5) == 30.5)
}

@Test func doubleSpeedRunsOnTwiceAsFast() {
    #expect(track(rate: 2).elapsed(at: reported + 10) == 50)
}

@Test func elapsedTimeStopsAtTheEndOfTheTrack() {
    // The source reports the next track a moment after this one ends.
    #expect(track(rate: 1).elapsed(at: reported + 600) == 240)
}

@Test func elapsedTimeNeverGoesBelowZero() {
    #expect(track(rate: 1).elapsed(at: reported - 60) == 0)
}

@Test func aLiveStreamRunsOnWithoutEnd() {
    #expect(track(rate: 1, duration: nil).elapsed(at: reported + 600) == 630)
}

@Test func aSeekMovesThePositionAndRunsOnFromThere() {
    let seekedAt = reported + 5
    let state = track(rate: 1).seeked(to: 120, at: seekedAt)
    #expect(state.elapsed(at: seekedAt) == 120)
    #expect(state.elapsed(at: seekedAt + 10) == 130)
    #expect(state.rate == 1)
    #expect(state.title == "Song")
}

@Test func aSeekWhilePausedStaysAtTheNewPosition() {
    let state = track(rate: 0).seeked(to: 120, at: reported + 5)
    #expect(state.elapsed(at: reported + 60) == 120)
}

@Test func aSeekStaysWithinTheTrack() {
    #expect(track(rate: 0).seeked(to: 999, at: reported).elapsed == 240)
    #expect(track(rate: 0).seeked(to: -5, at: reported).elapsed == 0)
}
