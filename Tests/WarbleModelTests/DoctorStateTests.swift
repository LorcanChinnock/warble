import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let macOS = Doctor.Version(26, 1)
private let working = Doctor.checks(Doctor.Facts(adapter: .working, macOS: macOS))
private let stopped = Doctor.Facts(adapter: .stopped(testStatus: 1), macOS: macOS, automation: [.music: .denied])

private func run(_ actions: AppAction...) -> (AppState, [AppEffect]) {
    var state = AppState(checks: working)
    var effects: [AppEffect] = []
    _ = reduce(&state, .housingsChanged([notch]), now: start)
    for action in actions {
        effects += reduce(&state, action, now: start)
    }
    return (state, effects)
}

@Test func whileTheAdapterWorksNothingIsChecked() {
    let (state, effects) = run(.hover(display: "built-in", .click), .playersChanged)
    #expect(!state.needsAttention)
    // Players opening and quitting aren't followed, so only an explicit change asks.
    #expect(effects.filter { if case .gatherFacts = $0 { true } else { false } }.count == 1)
}

@Test func theAdapterStoppingFollowsPlayersAndChecks() {
    let (state, effects) = run(.adapterChanged(.stopped(testStatus: 1)))
    #expect(effects == [.followPlayers(true), .gatherFacts(.stopped(testStatus: 1), pass: 1)])
    #expect(state.doctor.adapter == .stopped(testStatus: 1))
}

@Test func openingANotchChecksAgainOnlyWhenTheAdapterIsntWorking() {
    let (_, working) = run(.hover(display: "built-in", .click))
    #expect(!working.contains { if case .gatherFacts = $0 { true } else { false } })
    let (_, stopped) = run(.adapterChanged(.missing), .hover(display: "built-in", .click))
    #expect(stopped.last == .gatherFacts(.missing, pass: 2))
}

@Test func factsFromAnEarlierRefreshAreDropped() {
    let (state, _) = run(.adapterChanged(.stopped(testStatus: 1)), .playersChanged, .factsGathered(stopped, pass: 1))
    #expect(state.doctor.checks == working)
    let (latest, _) = run(.adapterChanged(.stopped(testStatus: 1)), .factsGathered(stopped, pass: 1))
    #expect(latest.doctor.checks == Doctor.checks(stopped))
    #expect(latest.needsAttention)
}

@Test func notNowHidesTheBangUntilAnotherCheckFails() {
    let (state, _) = run(.adapterChanged(.stopped(testStatus: 1)), .factsGathered(stopped, pass: 1), .notNow)
    #expect(!state.needsAttention)
    #expect(state.notchState("built-in") == .idle)
}

@Test func theFallbackChecksAgainOnlyWhileAutomationFails() {
    let (_, passing) = run(.fallbackReported)
    #expect(passing.isEmpty)
    let (_, failing) = run(.adapterChanged(.stopped(testStatus: 1)), .factsGathered(stopped, pass: 1), .fallbackReported)
    #expect(failing.last == .gatherFacts(.stopped(testStatus: 1), pass: 2))
}

@Test func theBangDrawsARestingNotchWithNothingPlaying() {
    let (state, _) = run(.adapterChanged(.missing), .factsGathered(Doctor.Facts(adapter: .missing, macOS: macOS), pass: 1))
    #expect(state.notchState("built-in") == .resting)
}
