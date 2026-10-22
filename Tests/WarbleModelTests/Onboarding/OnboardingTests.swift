import Foundation
import Testing
@testable import WarbleModel

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func aFirstLaunchAsksForTheWelcomeWindowOnce() {
    var state = AppState()
    #expect(reduce(&state, .launched(firstRun: true), now: now) == [.showWelcome])
    #expect(state.onboarding.welcome == .showing)
    #expect(reduce(&state, .launched(firstRun: true), now: now).isEmpty)
}

@Test func aLaterLaunchNeverAsksForTheWelcomeWindow() {
    var state = AppState()
    #expect(reduce(&state, .launched(firstRun: false), now: now).isEmpty)
    #expect(state.onboarding.welcome == .notShown)
}

@Test func closingTheWelcomeWindowDoesNotBringItBack() {
    var state = AppState()
    _ = reduce(&state, .launched(firstRun: true), now: now)
    #expect(reduce(&state, .welcomeClosed, now: now).isEmpty)
    #expect(state.onboarding.welcome == .closed)
    #expect(reduce(&state, .launched(firstRun: true), now: now).isEmpty)
}

@Test func theWelcomeWindowLeavesNoDeadlineWithNothingPlaying() {
    var state = AppState()
    _ = reduce(&state, .launched(firstRun: true), now: now)
    #expect(state.deadline == nil)
    _ = reduce(&state, .welcomeClosed, now: now)
    #expect(state.deadline == nil)
}
