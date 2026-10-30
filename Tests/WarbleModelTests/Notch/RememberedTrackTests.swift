import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)

private func idleAfterPause() -> (AppState, Date) {
    var state = AppState.pausingAfterTenSeconds()
    var now = start
    _ = reduce(&state, .housingsChanged([builtIn]), now: now)
    _ = reduce(&state, .playbackReported(song), now: now)
    var paused = song
    paused.rate = 0
    _ = reduce(&state, .playbackReported(paused), now: now)
    now += IdleAfterPause.delay
    _ = reduce(&state, .tick, now: now)
    return (state, now)
}

@Test func nothingIsRememberedUntilSomethingPlays() {
    var state = AppState.pausingAfterTenSeconds()
    _ = reduce(&state, .housingsChanged([builtIn]), now: start)
    #expect(state.lastPlayed == nil)
    _ = reduce(&state, .pointer(display: "built-in", inside: true), now: start)
    _ = reduce(&state, .tick, now: start + HoverIntent.expandDelay)
    #expect(state.notchState("built-in") == .note)
}

@Test func theIdleNotchOffersTheLastTrackInsteadOfTheNote() {
    var (state, now) = idleAfterPause()
    #expect(state.showsPlayback == false)
    #expect(state.lastPlayed?.title == "Song")
    _ = reduce(&state, .pointer(display: "built-in", inside: true), now: now)
    now += HoverIntent.expandDelay
    _ = reduce(&state, .tick, now: now)
    #expect(state.notchState("built-in") == .recall)
    #expect(!state.followsVolume)
}

@Test func theLastTrackIsForgottenOnceTheSourceStopsReportingAndReplacedByTheNextOne() {
    var state = AppState.pausingAfterTenSeconds()
    _ = reduce(&state, .playbackReported(song), now: start)
    _ = reduce(&state, .playbackReported(nil), now: start)
    #expect(state.lastPlayed == song)
    _ = reduce(&state, .tick, now: start + AppState.hideDelay)
    #expect(state.playback == nil)
    #expect(state.lastPlayed == nil)
    var next = song
    next.title = "Next"
    _ = reduce(&state, .playbackReported(next), now: start + 60)
    #expect(state.lastPlayed?.title == "Next")
}

@Test func resumingPlaysTheRememberedTrackOnlyWhileIdle() {
    var (state, now) = idleAfterPause()
    #expect(reduce(&state, .resumeLast, now: now) == [.send(.play)])
    _ = reduce(&state, .playbackReported(song), now: now)
    #expect(reduce(&state, .resumeLast, now: now).isEmpty)
    var fresh = AppState.pausingAfterTenSeconds()
    #expect(reduce(&fresh, .resumeLast, now: now).isEmpty)
}

@Test func theRememberedTrackCardHangsBelowTheHousingAndTakesTheHover() {
    let card = NotchLayout.frame(.recall, notch: builtIn.frame)
    #expect(card?.minY == builtIn.frame.minY - NotchLayout.recallDrop)
    #expect(NotchLayout.hoverArea(.recall, notch: builtIn.frame) == card)
    #expect(NotchState.recall.isOpen)
}
