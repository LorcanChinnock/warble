import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let paused = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: start, rate: 0)

@MainActor
private func store() -> (Store, FakeClock, FakeScheduler) {
    let clock = FakeClock(start)
    let scheduler = FakeScheduler()
    return (Store(state: AppState(), clock: clock, scheduler: scheduler), clock, scheduler)
}

@MainActor
@Test func withNothingPlayingTheStoreArmsNoTimer() {
    let (store, _, scheduler) = store()
    store.dispatch(.housingsChanged([NotchHousing(display: "built-in", frame: .zero, isVirtual: false)]))
    store.dispatch(.sourceReported(bundleIdentifier: "app", nil))
    store.dispatch(.dismiss(except: nil))
    #expect(scheduler.armed == 0)
    #expect(scheduler.deadline == nil)
}

@MainActor
@Test func theStoreArmsOneTimerForTheEarliestDeadlineAndTicksAtIt() {
    let (store, clock, scheduler) = store()
    store.dispatch(.sourceReported(bundleIdentifier: "app", paused))
    #expect(scheduler.deadline == start + IdleAfterPause.defaultDelay)
    // Nothing new is due, so the timer stays as it is.
    store.dispatch(.sourceReported(bundleIdentifier: "app", paused))
    #expect(scheduler.armed == 1)
    // The timer fires a moment early; the tick still counts as at the deadline.
    clock.now = start + IdleAfterPause.defaultDelay - 0.001
    scheduler.run()
    #expect(!store.state.showsPlayback)
    #expect(scheduler.deadline == nil)
}

@MainActor
@Test func theStoreCancelsItsTimerWhenNothingIsDue() {
    let (store, _, scheduler) = store()
    store.dispatch(.housingsChanged([NotchHousing(display: "built-in", frame: .zero, isVirtual: false)]))
    store.dispatch(.sourceReported(bundleIdentifier: "app", paused))
    // Pinned open, the notch holds the pause's countdown off.
    store.dispatch(.hover(display: "built-in", .click))
    store.dispatch(.hover(display: "built-in", .click))
    #expect(scheduler.deadline == nil)
}

@MainActor
@Test func everyActionReportsTheStateBeforeAndAfter() {
    let (store, _, _) = store()
    var changes: [(AppState, AppState)] = []
    store.onChange = { old, new, _ in changes.append((old, new)) }
    store.dispatch(.sourceReported(bundleIdentifier: "app", paused))
    #expect(changes.count == 1)
    #expect(changes[0].0.playback == nil)
    #expect(changes[0].1.playback == paused)
}
