import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func track(_ title: String = "Song", playing: Bool) -> PlaybackState {
    PlaybackState(bundleIdentifier: "com.apple.Music", title: title, artist: "Artist", elapsedTimestamp: start, rate: playing ? 1 : 0)
}

private func idle(_ events: (IdleEvent, TimeInterval)...) -> IdleAfterPause {
    var idle = IdleAfterPause()
    for (event, offset) in events {
        idle.handle(event, at: start + offset)
    }
    return idle
}

@Test func withNothingPlayingTheNotchIsIdleWithNothingDue() {
    let nothing = IdleAfterPause()
    #expect(nothing.isIdle)
    #expect(nothing.deadline == nil)
}

@Test func whilePlayingTheNotchNeverGoesIdle() {
    var playing = idle((.playback(track(playing: true)), 0))
    #expect(!playing.isIdle)
    #expect(playing.deadline == nil)
    playing.advance(to: start + 3600)
    #expect(!playing.isIdle)
}

@Test func pausingGoesIdleAfterTenSeconds() {
    var paused = idle((.playback(track(playing: true)), 0), (.playback(track(playing: false)), 5))
    #expect(paused.deadline == start + 15)
    paused.advance(to: start + 14.9)
    #expect(!paused.isIdle)
    paused.advance(to: start + 15)
    #expect(paused.isIdle)
    #expect(paused.deadline == nil)
}

@Test func playingAgainBeforeTheDeadlineCancelsIt() {
    var resumed = idle(
        (.playback(track(playing: true)), 0), (.playback(track(playing: false)), 5), (.playback(track(playing: true)), 12)
    )
    #expect(resumed.deadline == nil)
    resumed.advance(to: start + 60)
    #expect(!resumed.isIdle)
}

@Test func pausingAgainWaitsTheFullDelay() {
    let again = idle(
        (.playback(track(playing: true)), 0), (.playback(track(playing: false)), 5),
        (.playback(track(playing: true)), 12), (.playback(track(playing: false)), 13)
    )
    #expect(again.deadline == start + 23)
}

@Test func aNewTrackWhilePausedRestartsTheCountdown() {
    var skipped = idle((.playback(track(playing: false)), 0), (.playback(track("Next", playing: false)), 8))
    #expect(skipped.deadline == start + 18)
    skipped.advance(to: start + 17)
    #expect(!skipped.isIdle)
}

@Test func aNewPausedTrackAfterIdleShowsItAgain() {
    var back = idle((.playback(track(playing: false)), 0))
    back.advance(to: start + 10)
    #expect(back.isIdle)
    back.handle(.playback(track("Next", playing: false)), at: start + 30)
    #expect(!back.isIdle)
    #expect(back.deadline == start + 40)
}

@Test func moreReportsOfTheSamePausedTrackLeaveTheCountdownAlone() {
    var seeked = idle((.playback(track(playing: false)), 0))
    var moved = track(playing: false)
    moved.elapsed = 42
    seeked.handle(.playback(moved), at: start + 6)
    #expect(seeked.deadline == start + 10)
    seeked.advance(to: start + 10)
    seeked.handle(.playback(moved), at: start + 11)
    #expect(seeked.isIdle)
}

@Test func hoveringHoldsAPausedTrackOnScreen() {
    var hovered = idle((.playback(track(playing: false)), 0), (.hoverStarted, 4))
    #expect(hovered.deadline == nil)
    hovered.advance(to: start + 60)
    #expect(!hovered.isIdle)
}

@Test func theCountdownRestartsWhenThePointerLeaves() {
    var left = idle((.playback(track(playing: false)), 0), (.hoverStarted, 4), (.hoverEnded, 30))
    #expect(left.deadline == start + 40)
    left.advance(to: start + 39)
    #expect(!left.isIdle)
    left.advance(to: start + 40)
    #expect(left.isIdle)
}

@Test func pausingFromTheOpenCardCountsDownOnceThePointerLeaves() {
    let fromCard = idle(
        (.playback(track(playing: true)), 0), (.hoverStarted, 1), (.playback(track(playing: false)), 2), (.hoverEnded, 3)
    )
    #expect(fromCard.deadline == start + 13)
}

@Test func thePointerLeavingWhilePlayingStartsNoCountdown() {
    let playing = idle((.playback(track(playing: true)), 0), (.hoverStarted, 1), (.hoverEnded, 2))
    #expect(playing.deadline == nil)
}

@Test func aSourceThatStopsReportingGoesIdleAtOnce() {
    let stopped = idle((.playback(track(playing: true)), 0), (.hoverStarted, 1), (.playback(nil), 2))
    #expect(stopped.isIdle)
    #expect(stopped.deadline == nil)
}

@Test func aLateTimerStillGoesIdle() {
    var late = idle((.playback(track(playing: false)), 0))
    late.advance(to: start + 300)
    #expect(late.isIdle)
}

@Test func theDelayStartsAtTenSeconds() {
    #expect(IdleAfterPause().pauseDelay == .tenSeconds)
    #expect(PauseDelay.tenSeconds.seconds == IdleAfterPause.delay)
}

@Test func aMinuteKeepsAPausedTrackForAMinute() {
    var paused = idle((.playback(track(playing: true)), 0), (.playback(track(playing: false)), 5))
    paused.pauseDelay = .oneMinute
    #expect(paused.deadline == start + 65)
    paused.advance(to: start + 64.9)
    #expect(!paused.isIdle)
    paused.advance(to: start + 65)
    #expect(paused.isIdle)
}

@Test func alwaysNeverGoesIdleAfterAPauseAndSchedulesNothing() {
    var paused = IdleAfterPause()
    paused.pauseDelay = .always
    paused.handle(.playback(track(playing: true)), at: start)
    paused.handle(.playback(track(playing: false)), at: start + 5)
    #expect(paused.deadline == nil)
    paused.advance(to: start + 86_400)
    #expect(!paused.isIdle)
}

@Test func alwaysStillGoesIdleAtOnceWhenTheSourceStops() {
    var paused = IdleAfterPause()
    paused.pauseDelay = .always
    paused.handle(.playback(track(playing: false)), at: start)
    paused.handle(.playback(nil), at: start + 1)
    #expect(paused.isIdle)
}

@Test func aNewDelayAppliesToATrackThatIsAlreadyPaused() {
    var paused = idle((.playback(track(playing: true)), 0), (.playback(track(playing: false)), 5))
    paused.pauseDelay = .always
    #expect(paused.deadline == nil)
    paused.pauseDelay = .oneMinute
    #expect(paused.deadline == start + 65)
}
