import Foundation
import Testing
@testable import WarbleModel

/// Feeds a gesture of `count` events `step` seconds apart, each moving `dx` and `dy`, and returns what each did.
private func scroll(dx: Double = 0, dy: Double = 0, count: Int, step: TimeInterval, inverted: Bool = true) -> [ScrollGesture.Outcome] {
    var gesture = ScrollGesture()
    var outcomes: [ScrollGesture.Outcome] = []
    for index in 0..<count {
        let phase: ScrollGesture.Phase = index == 0 ? .began : .changed
        if let outcome = gesture.handle(dx: dx, dy: dy, precise: true, inverted: inverted, phase: phase, at: Double(index) * step) {
            outcomes.append(outcome)
        }
    }
    if let outcome = gesture.handle(dx: 0, dy: 0, precise: true, inverted: inverted, phase: .ended, at: Double(count) * step) {
        outcomes.append(outcome)
    }
    return outcomes
}

private func isScrub(_ outcome: ScrollGesture.Outcome) -> Bool {
    if case .scrub = outcome { true } else { false }
}

@Test func scrollingUpAndDownSetsTheVolume() {
    let outcomes = scroll(dy: -5, count: 10, step: 0.01)
    // The first event is under the distance a gesture needs to pick a direction, so the second carries both.
    #expect(outcomes.first == .volume(-10))
    #expect(outcomes.count == 9)
    #expect(outcomes.allSatisfy { if case .volume = $0 { true } else { false } })
}

@Test func aMouseWheelOnlySetsTheVolume() {
    var gesture = ScrollGesture()
    #expect(gesture.handle(dx: 3, dy: 0, precise: false, inverted: false, phase: .changed, at: 0) == nil)
    #expect(gesture.handle(dx: 0, dy: 1, precise: false, inverted: false, phase: .changed, at: 0.1) == .volume(1))
}

@Test func aGestureThatStartsVerticalIgnoresSidewaysDrift() {
    var gesture = ScrollGesture()
    #expect(gesture.handle(dx: 0, dy: 8, precise: true, inverted: true, phase: .began, at: 0) == .volume(8))
    #expect(gesture.handle(dx: 40, dy: 2, precise: true, inverted: true, phase: .changed, at: 0.01) == .volume(2))
    #expect(gesture.handle(dx: 0, dy: 0, precise: true, inverted: true, phase: .ended, at: 0.02) == nil)
}

@Test func coastingAfterFingersLiftDoesNothing() {
    var gesture = ScrollGesture()
    #expect(gesture.handle(dx: 0, dy: 20, precise: true, inverted: true, phase: .momentum, at: 0) == nil)
}

@Test func aSlowSlideSidewaysMovesThroughTheSong() {
    // 2 points every 10 ms is 200 points a second: well under a flick.
    let outcomes = scroll(dx: 2, count: 50, step: 0.01)
    let total = outcomes.reduce(0.0) { sum, outcome in
        if case .scrub(let seconds) = outcome { sum + seconds } else { sum }
    }
    #expect(!outcomes.contains(.skip(next: true)) && !outcomes.contains(.skip(next: false)))
    // With natural scrolling, fingers moving right is a positive delta, and 100 points is 20 seconds.
    #expect(abs(total - 20) < 0.001)
    #expect(outcomes.count < 50)
}

@Test func fingersMovingRightMoveBackWithoutNaturalScrolling() {
    // Without natural scrolling, fingers moving right reports a negative delta.
    let outcomes = scroll(dx: -2, count: 20, step: 0.01, inverted: false)
    #expect(!outcomes.isEmpty)
    #expect(outcomes.allSatisfy { if case .scrub(let seconds) = $0 { seconds > 0 } else { false } })
}

@Test func aQuickFlickRightSkipsToTheNextTrack() {
    // 30 points every 10 ms is 3000 points a second.
    #expect(scroll(dx: 30, count: 6, step: 0.01).last == .skip(next: true))
}

@Test func aQuickFlickLeftGoesBack() {
    #expect(scroll(dx: -30, count: 6, step: 0.01).last == .skip(next: false))
}

@Test func aSmallQuickTwitchDoesNotSkip() {
    let outcomes = scroll(dx: -8, count: 3, step: 0.005)
    #expect(!outcomes.contains(.skip(next: true)))
}

@Test func aFlickStopsMovingThroughTheSongOnceItIsFast() {
    #expect(scroll(dx: -30, count: 6, step: 0.01).filter(isScrub).count <= 1)
}
