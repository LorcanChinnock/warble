import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)

private func episode(
    _ title: String = "Episode", duration: TimeInterval? = 1_800, elapsed: TimeInterval = 0, playing: Bool = true
) -> PlaybackState {
    PlaybackState(
        bundleIdentifier: "com.apple.podcasts", title: title, duration: duration, elapsed: elapsed, elapsedTimestamp: start,
        rate: playing ? 1 : 0
    )
}

/// A state with the setting on and `playback` playing from `start`, with a timer chosen at `start` if `choice` is given.
private func playing(_ playback: PlaybackState = episode(), choosing choice: SleepTimer.Choice? = nil, setting: Bool = true) -> AppState {
    var state = AppState(showsSleepTimer: setting)
    _ = reduce(&state, .housingsChanged([notch]), now: start)
    _ = reduce(&state, .playbackReported(playback), now: start)
    if let choice {
        _ = reduce(&state, .setSleepTimer(choice), now: start)
    }
    return state
}

@Test func aFixedTimerIsDueThatLongAfterItStarts() {
    #expect(playing(choosing: .fifteenMinutes).sleepTimer?.deadline == start + 15 * 60)
    #expect(playing(choosing: .thirtyMinutes).sleepTimer?.deadline == start + 30 * 60)
    #expect(playing(choosing: .oneHour).sleepTimer?.deadline == start + 60 * 60)
    #expect(playing(choosing: .oneHour).deadline == start + 60 * 60)
}

@Test func whenAFixedTimerIsDueItPausesOnceShowsThePauseAndClearsTheTimer() {
    var state = playing(choosing: .fifteenMinutes)
    let due = start + 15 * 60
    let early = reduce(&state, .tick, now: due - 1)
    #expect(early.isEmpty)
    #expect(state.sleepTimer != nil)
    let effects = reduce(&state, .tick, now: due)
    #expect(effects == [.send(.pause)])
    #expect(state.playback?.isPlaying == false)
    #expect(state.sleepTimer == nil)
    // The notch then behaves as after any pause: it goes Idle after the usual delay.
    #expect(state.idle.deadline == due + IdleAfterPause.defaultDelay)
    #expect(reduce(&state, .tick, now: due + 1).isEmpty)
}

@Test func endOfTrackIsDueWhenTheTrackEnds() {
    let state = playing(episode(duration: 600, elapsed: 100), choosing: .endOfTrack)
    #expect(state.sleepTimer?.deadline == start + 500)
    #expect(state.deadline == start + 500)
    var due = state
    #expect(reduce(&due, .tick, now: start + 500) == [.send(.pause)])
    #expect(due.sleepTimer == nil)
}

@Test func endOfTrackFollowsTheRate() {
    var fast = episode(duration: 600, elapsed: 100)
    fast.rate = 2
    #expect(playing(fast, choosing: .endOfTrack).sleepTimer?.deadline == start + 250)
}

@Test func aSeekMovesTheEndOfTrackDeadline() {
    var state = playing(episode(duration: 600, elapsed: 100), choosing: .endOfTrack)
    var seeked = episode(duration: 600, elapsed: 300)
    seeked.elapsedTimestamp = start + 10
    _ = reduce(&state, .playbackReported(seeked), now: start + 10)
    #expect(state.sleepTimer?.deadline == start + 10 + 300)
    #expect(state.deadline == start + 310)
}

@Test func aNewTrackReportedBeforeTheEndPausesAtOnce() {
    var state = playing(episode(duration: 600, elapsed: 100), choosing: .endOfTrack)
    let next = PlaybackState(bundleIdentifier: "com.apple.podcasts", title: "Next", duration: 900, elapsedTimestamp: start + 400, rate: 1)
    let effects = reduce(&state, .playbackReported(next), now: start + 400)
    #expect(effects.contains(.send(.pause)))
    #expect(state.playback?.title == "Next")
    #expect(state.playback?.isPlaying == false)
    #expect(state.sleepTimer == nil)
}

@Test func endOfTrackNeedsATrackWithALength() {
    let live = playing(episode(duration: nil), choosing: .endOfTrack)
    #expect(live.sleepTimer == nil)
    #expect(live.deadline == nil)
}

@Test func turningTheTimerOffClearsTheDeadlineAndSendsNothing() {
    var state = playing(choosing: .thirtyMinutes)
    #expect(reduce(&state, .setSleepTimer(nil), now: start + 5).isEmpty)
    #expect(state.sleepTimer == nil)
    #expect(state.deadline == nil)
}

@Test func turningTheSettingOffCancelsARunningTimerAndSendsNothing() {
    var state = playing(choosing: .thirtyMinutes)
    #expect(reduce(&state, .sleepTimerSettingChanged(false), now: start + 5).isEmpty)
    #expect(state.sleepTimer == nil)
    #expect(state.deadline == nil)
}

@Test func withTheSettingOffNoTimerStarts() {
    let state = playing(choosing: .fifteenMinutes, setting: false)
    #expect(state.sleepTimer == nil)
    #expect(state.deadline == nil)
}

@Test func aPauseByHandCancelsTheTimer() {
    var state = playing(choosing: .thirtyMinutes)
    let effects = reduce(&state, .command(.togglePlayPause), now: start + 20)
    #expect(effects == [.send(.togglePlayPause)])
    #expect(state.sleepTimer == nil)
    // Playing again doesn't bring it back.
    _ = reduce(&state, .command(.play), now: start + 30)
    #expect(state.sleepTimer == nil)
}

@Test func aPauseInTheAppCancelsTheTimer() {
    var state = playing(choosing: .thirtyMinutes)
    _ = reduce(&state, .playbackReported(episode(playing: false)), now: start + 20)
    #expect(state.sleepTimer == nil)
}

@Test func noTimerStartsWhilePausedOrWithNothingPlaying() {
    var paused = playing(episode(playing: false))
    _ = reduce(&paused, .setSleepTimer(.fifteenMinutes), now: start)
    #expect(paused.sleepTimer == nil)
    var nothing = AppState(showsSleepTimer: true)
    _ = reduce(&nothing, .setSleepTimer(.fifteenMinutes), now: start)
    #expect(nothing.sleepTimer == nil)
    #expect(nothing.deadline == nil)
}

@Test func whenTheSourceStopsReportingTheTimerEndsWithTheNotch() {
    var state = playing(choosing: .thirtyMinutes)
    _ = reduce(&state, .playbackReported(nil), now: start + 60)
    _ = reduce(&state, .tick, now: start + 60 + AppState.hideDelay)
    #expect(state.sleepTimer == nil)
    #expect(state.deadline == nil)
}

@Test func choosingANewTimeReplacesTheOneRunning() {
    var state = playing(choosing: .oneHour)
    _ = reduce(&state, .setSleepTimer(.fifteenMinutes), now: start + 60)
    #expect(state.sleepTimer?.choice == .fifteenMinutes)
    #expect(state.deadline == start + 60 + 15 * 60)
}

@MainActor
private func store(_ state: AppState) -> (Store, FakeClock, FakeScheduler) {
    let clock = FakeClock(start)
    let scheduler = FakeScheduler()
    return (Store(state: state, clock: clock, scheduler: scheduler), clock, scheduler)
}

@MainActor
@Test func theStoreArmsOneTimerForTheTimerAndPausesWhenItFires() {
    let (store, clock, scheduler) = store(AppState(showsSleepTimer: true))
    var sent: [AppEffect] = []
    store.perform = { sent.append($0) }
    store.dispatch(.housingsChanged([notch]))
    store.dispatch(.playbackReported(episode()))
    #expect(scheduler.deadline == nil)
    store.dispatch(.setSleepTimer(.fifteenMinutes))
    #expect(scheduler.deadline == start + 15 * 60)
    let armed = scheduler.armed
    // Choosing another time re-arms the one timer rather than adding a second.
    store.dispatch(.setSleepTimer(.thirtyMinutes))
    #expect(scheduler.deadline == start + 30 * 60)
    #expect(scheduler.armed == armed + 1)
    clock.now = start + 30 * 60
    scheduler.run()
    #expect(sent.filter { $0 == .send(.pause) }.count == 1)
    #expect(store.state.sleepTimer == nil)
    // What's left is Idle's countdown after the pause; the timer adds nothing.
    #expect(scheduler.deadline == start + 30 * 60 + IdleAfterPause.defaultDelay)
}

@MainActor
@Test func theStoreArmsNoTimerWithNothingPlayingOrOnceIdle() {
    let (store, clock, scheduler) = store(AppState(showsSleepTimer: true))
    store.dispatch(.housingsChanged([notch]))
    store.dispatch(.setSleepTimer(.fifteenMinutes))
    #expect(scheduler.armed == 0)
    store.dispatch(.playbackReported(episode()))
    store.dispatch(.setSleepTimer(.fifteenMinutes))
    #expect(scheduler.deadline != nil)
    // The listener pauses; the timer goes, and so does the notch after its delay.
    store.dispatch(.command(.pause))
    #expect(scheduler.deadline == start + IdleAfterPause.defaultDelay)
    clock.now = start + IdleAfterPause.defaultDelay
    scheduler.run()
    #expect(!store.state.showsPlayback)
    #expect(scheduler.deadline == nil)
}

@Test func theGapBetweenTracksKeepsAFixedTimer() {
    var state = playing(choosing: .thirtyMinutes)
    _ = reduce(&state, .playbackReported(nil), now: start + 60)
    #expect(state.sleepTimer?.deadline == start + 30 * 60)
    _ = reduce(&state, .playbackReported(episode("Next")), now: start + 61)
    #expect(state.sleepTimer?.deadline == start + 30 * 60)
}

@Test func aNewTrackAfterTheGapPausesAnEndOfTrackTimer() {
    var state = playing(episode(duration: 600, elapsed: 100), choosing: .endOfTrack)
    #expect(reduce(&state, .playbackReported(nil), now: start + 499).isEmpty)
    #expect(state.sleepTimer != nil)
    let next = PlaybackState(bundleIdentifier: "com.apple.podcasts", title: "Next", duration: 900, elapsedTimestamp: start + 500, rate: 1)
    let effects = reduce(&state, .playbackReported(next), now: start + 500)
    #expect(effects.contains(.send(.pause)))
    #expect(state.playback?.isPlaying == false)
    #expect(state.sleepTimer == nil)
}

@Test func aTimerDueInTheGapPausesWithoutKeepingTheTrackOnScreen() {
    var state = playing(choosing: .fifteenMinutes)
    _ = reduce(&state, .playbackReported(nil), now: start + 15 * 60 - 1)
    let effects = reduce(&state, .tick, now: start + 15 * 60)
    #expect(effects == [.send(.pause)])
    #expect(state.sleepTimer == nil)
    _ = reduce(&state, .tick, now: start + 15 * 60 - 1 + AppState.hideDelay)
    #expect(state.playback == nil)
}
