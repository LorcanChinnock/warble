import Foundation
import Testing
@testable import WarbleModel

private let now = Date(timeIntervalSince1970: 1_000_000)
private let housing = NotchHousing(display: "built-in", frame: CGRect(x: 100, y: 0, width: 185, height: 32), isVirtual: false)
private let playing = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: now, rate: 1)

/// A first launch with a notch drawn, and the time the demo's last step ends.
private func launched(firstRun: Bool = true) -> AppState {
    var state = AppState()
    _ = reduce(&state, .housingsChanged([housing]), now: now)
    _ = reduce(&state, .launched(firstRun: firstRun), now: now)
    return state
}

private let demoLength = NotchMotion.demoResting + NotchMotion.demoExpanded + NotchMotion.demoHint

@Test func aFirstLaunchStartsTheDemoAndHoldsTheWelcomeWindowBack() {
    var state = AppState()
    #expect(reduce(&state, .launched(firstRun: true), now: now).isEmpty)
    #expect(state.onboarding.demo.step == .resting)
    #expect(state.onboarding.welcome == .waiting)
    #expect(reduce(&state, .launched(firstRun: true), now: now).isEmpty)
}

@Test func aLaterLaunchNeverStartsTheDemoOrAsksForTheWelcomeWindow() {
    var state = AppState()
    #expect(reduce(&state, .launched(firstRun: false), now: now).isEmpty)
    #expect(state.onboarding.demo.step == nil)
    #expect(state.onboarding.welcome == .notShown)
    #expect(state.deadline == nil)
}

@Test func eachTickMovesTheDemoOnAndTheLastOneAsksForTheWelcomeWindow() {
    var state = launched()
    #expect(state.notchState("built-in") == .resting)
    #expect(state.deadline == now + NotchMotion.demoResting)

    _ = reduce(&state, .tick, now: now + NotchMotion.demoResting)
    #expect(state.onboarding.demo.step == .expanded)
    #expect(state.notchState("built-in") == .expanded)
    #expect(state.card("built-in") == .player)

    _ = reduce(&state, .tick, now: now + NotchMotion.demoResting + NotchMotion.demoExpanded)
    #expect(state.onboarding.demo.step == .hint)
    #expect(state.notchState("built-in") == .hint)

    #expect(reduce(&state, .tick, now: now + demoLength) == [.showWelcome])
    #expect(state.onboarding.demo.step == nil)
    #expect(state.onboarding.welcome == .showing)
    #expect(state.deadline == nil)
    #expect(state.notchState("built-in") == .idle)
}

@Test func aLateTickSkipsTheStepsThatWouldHaveEnded() {
    var state = launched()
    _ = reduce(&state, .tick, now: now + NotchMotion.demoResting + NotchMotion.demoExpanded + 1)
    #expect(state.onboarding.demo.step == .hint)
    #expect(state.deadline == now + demoLength)
}

@Test func theDemoDrawsNothingExtraOnceItHasEnded() {
    var state = launched()
    _ = reduce(&state, .tick, now: now + demoLength)
    _ = reduce(&state, .welcomeClosed, now: now + demoLength)
    #expect(state.onboarding.welcome == .closed)
    #expect(state.notchState("built-in") == .idle)
    #expect(state.deadline == nil)
}

@Test func theDemoEndsAtOnceWhenThePointerComesOnTheNotch() {
    var state = launched()
    #expect(reduce(&state, .pointer(display: "built-in", inside: true), now: now + 1) == [.showWelcome])
    #expect(state.onboarding.demo.step == nil)
    #expect(state.deadline != nil)
    // The notch carries on as usual: the pointer on the idle notch opens the idle card after the hover delay.
    #expect(state.notchState("built-in") == .idle)
    _ = reduce(&state, .tick, now: state.deadline!)
    #expect(state.notchState("built-in") == .expanded)
    #expect(state.card("built-in") == .idle)
}

@Test(arguments: [HoverEvent.click, .keyboard])
func aClickOrTheKeyboardEndsTheDemoAtOnce(_ event: HoverEvent) {
    var state = launched()
    #expect(reduce(&state, .hover(display: "built-in", event), now: now + 1).contains(.showWelcome))
    #expect(state.onboarding.demo.step == nil)
}

@Test func somethingPlayingEndsTheDemoAtOnce() {
    var state = launched()
    #expect(reduce(&state, .sourceReported(bundleIdentifier: "app", playing), now: now + 1).contains(.showWelcome))
    #expect(state.onboarding.demo.step == nil)
    #expect(state.notchState("built-in") == .resting)
}

@Test func aReportOfNothingOrAPauseLeavesTheDemoAlone() {
    var state = launched()
    _ = reduce(&state, .sourceReported(bundleIdentifier: "app", nil), now: now + 1)
    var paused = playing
    paused.rate = 0
    _ = reduce(&state, .sourceReported(bundleIdentifier: "app", paused), now: now + 1)
    #expect(state.onboarding.demo.step == .resting)
}

@Test func somethingAlreadyPlayingAtLaunchSkipsTheDemo() {
    var state = AppState()
    _ = reduce(&state, .sourceReported(bundleIdentifier: "app", playing), now: now)
    #expect(reduce(&state, .launched(firstRun: true), now: now) == [.showWelcome])
    #expect(state.onboarding.demo.step == nil)
}

@Test func endingTheDemoTwiceAsksForTheWelcomeWindowOnce() {
    var state = launched()
    _ = reduce(&state, .pointer(display: "built-in", inside: true), now: now + 1)
    #expect(!reduce(&state, .hover(display: "built-in", .click), now: now + 2).contains(.showWelcome))
}

@Test func closingTheWelcomeWindowDoesNotBringItOrTheDemoBack() {
    var state = launched()
    _ = reduce(&state, .tick, now: now + demoLength)
    #expect(reduce(&state, .welcomeClosed, now: now + demoLength).isEmpty)
    #expect(state.onboarding.welcome == .closed)
    #expect(reduce(&state, .launched(firstRun: true), now: now + demoLength).isEmpty)
    #expect(state.onboarding.demo.step == nil)
}

@MainActor
@Test func theStoreArmsTheDemosTimerAndNoneOnceItHasEnded() {
    let clock = FakeClock(now)
    let scheduler = FakeScheduler()
    let store = Store(state: AppState(), clock: clock, scheduler: scheduler)
    store.dispatch(.housingsChanged([housing]))
    #expect(scheduler.deadline == nil)
    store.dispatch(.launched(firstRun: true))
    #expect(scheduler.deadline == now + NotchMotion.demoResting)
    clock.now = now + demoLength
    scheduler.run()
    #expect(store.state.onboarding.demo.step == nil)
    #expect(scheduler.deadline == nil)
}

@Test func theHintReachesBelowTheHousingAndTakesTheHoverOnlyOverTheHousing() throws {
    let frame = try #require(NotchLayout.frame(.hint, notch: housing.frame))
    #expect(frame.height == housing.frame.height + NotchLayout.hintDrop)
    #expect(frame.contains(housing.frame))
    #expect(NotchLayout.hoverArea(.hint, notch: housing.frame) == housing.frame)
}

@Test func theOpenNotchShortcutEndsTheDemoBeforeItAsksForTheKeyboard() {
    var state = launched()
    let effects = reduce(&state, .perform(.openNotch), now: now + 1)
    #expect(effects.contains(.showWelcome))
    #expect(effects.contains(.toggleKeyboard))
    // The notch is already the idle one when the keyboard is asked to open it, so it counts as opening.
    #expect(state.notchState("built-in") == .idle)
}

@Test func theDemoDrawsItsTrackWhileLeavingWhatTheSourcesSaidAlone() {
    var state = launched()
    #expect(state.demoTrackStart == now)
    #expect(state.drawsPlayback)
    #expect(state.playback == nil)
    #expect(state.notchState("built-in") == .resting)

    _ = reduce(&state, .tick, now: now + NotchMotion.demoResting + NotchMotion.demoExpanded)
    #expect(state.notchState("built-in") == .hint)
    #expect(state.demoTrackStart == nil)
    #expect(!state.drawsPlayback)
}
