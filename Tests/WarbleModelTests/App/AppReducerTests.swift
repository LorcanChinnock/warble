import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func track(_ title: String = "Song", playing: Bool = true) -> PlaybackState {
    PlaybackState(bundleIdentifier: "com.apple.Music", title: title, artist: "Artist", elapsedTimestamp: start, rate: playing ? 1 : 0)
}

private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)

private func state(_ actions: (AppAction, TimeInterval)...) -> AppState {
    var state = AppState()
    _ = reduce(&state, .housingsChanged([notch]), now: start)
    for (action, offset) in actions {
        _ = reduce(&state, action, now: start + offset)
    }
    return state
}

@Test func withNothingPlayingNothingIsDue() {
    let nothing = state((.playbackReported(nil), 0), (.tick, 3))
    #expect(nothing.playback == nil)
    #expect(!nothing.showsPlayback)
    #expect(nothing.deadline == nil)
}

@Test func aSkipDoesntCloseTheNotch() {
    var skipping = state((.playbackReported(track()), 0), (.playbackReported(nil), 10))
    #expect(skipping.playback == track())
    #expect(skipping.deadline == start + 10 + AppState.hideDelay)
    _ = reduce(&skipping, .playbackReported(track("Next")), now: start + 10.5)
    #expect(skipping.playback == track("Next"))
    #expect(skipping.hideAt == nil)
    #expect(skipping.deadline == nil)
    #expect(skipping.showsPlayback)
}

@Test func aSourceThatStopsReportingHidesAfterTheDelayAndGoesIdle() {
    var stopped = state((.playbackReported(track()), 0), (.playbackReported(nil), 10))
    _ = reduce(&stopped, .tick, now: start + 11.4)
    #expect(stopped.playback != nil)
    _ = reduce(&stopped, .tick, now: start + 10 + AppState.hideDelay)
    #expect(stopped.playback == nil)
    #expect(!stopped.showsPlayback)
    #expect(stopped.deadline == nil)
}

@Test func eachReportOfNothingWaitsAgain() {
    let waiting = state((.playbackReported(track()), 0), (.playbackReported(nil), 10), (.playbackReported(nil), 11))
    #expect(waiting.hideAt == start + 11 + AppState.hideDelay)
}

@Test func pausingGoesIdleAfterTheDelay() {
    var paused = state((.playbackReported(track()), 0), (.playbackReported(track(playing: false)), 5))
    #expect(paused.deadline == start + 5 + IdleAfterPause.delay)
    _ = reduce(&paused, .tick, now: start + 14.9)
    #expect(paused.showsPlayback)
    _ = reduce(&paused, .tick, now: start + 15)
    #expect(!paused.showsPlayback)
    #expect(paused.deadline == nil)
}

@Test func resumingBeforeTheDeadlineCancelsIt() {
    let resumed = state((.playbackReported(track()), 0), (.playbackReported(track(playing: false)), 5), (.playbackReported(track()), 8), (.tick, 15))
    #expect(resumed.showsPlayback)
    #expect(resumed.deadline == nil)
}

@Test func hoverHoldsAPausedTrackAndLeavingStartsTheWaitAgain() {
    // A click pins the notch open, so only the pause's countdown could be due, and the pointer holds it.
    var held = state((.playbackReported(track(playing: false)), 0), (.hover(display: "built-in", .click), 2), (.hover(display: "built-in", .click), 2))
    #expect(held.hovering)
    #expect(held.deadline == nil)
    _ = reduce(&held, .tick, now: start + 60)
    #expect(held.showsPlayback)
    _ = reduce(&held, .dismiss(except: nil), now: start + 60)
    #expect(!held.hovering)
    #expect(held.deadline == start + 60 + IdleAfterPause.delay)
}

@Test func settingsChangeHowLongAPausedSongStays() {
    var state = AppState()
    _ = reduce(&state, .playbackReported(PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: start, rate: 1)), now: start)
    _ = reduce(&state, .playbackReported(PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: start, rate: 0)), now: start + 5)
    #expect(state.deadline == start + 5 + IdleAfterPause.delay)
    _ = reduce(&state, .pauseDelayChanged(.oneMinute), now: start + 6)
    #expect(state.deadline == start + 5 + 60)
    _ = reduce(&state, .pauseDelayChanged(.always), now: start + 7)
    #expect(state.deadline == nil)
    #expect(state.showsPlayback)
}

@Test func theAlbumArtGlowStartsOn() {
    #expect(AppState().showsGlow)
}

@Test func settingsTurnTheAlbumArtGlowOffAndOn() {
    var state = AppState()
    let effects = reduce(&state, .glowChanged(false), now: start)
    #expect(!state.showsGlow)
    #expect(effects.isEmpty)
    #expect(state.deadline == nil)
    _ = reduce(&state, .glowChanged(true), now: start + 1)
    #expect(state.showsGlow)
}

@Test func settingsChooseTheCardSize() {
    var state = AppState()
    #expect(state.cardSize == .standard)
    let effects = reduce(&state, .cardSizeChanged(.large), now: start)
    #expect(state.cardSize == .large)
    #expect(effects.isEmpty)
    #expect(state.deadline == nil)
}
