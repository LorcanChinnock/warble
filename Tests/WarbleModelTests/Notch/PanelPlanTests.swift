import Foundation
import Testing
@testable import WarbleModel

private let small = CGRect(x: 100, y: 100, width: 200, height: 40)
private let large = CGRect(x: 50, y: 20, width: 300, height: 120)

private func plan(
    _ state: NotchState = .expanded, target: CGRect? = large, playing: Bool = true, animated: Bool = true,
    shown: (NotchState, CGRect)? = nil, panel: CGRect? = nil, wasPlaying: Bool = true
) -> PanelPlan {
    PanelPlan.make(
        state: state, target: target, isPlaying: playing, animated: animated,
        shown: shown.map { (state: $0.0, frame: $0.1) }, panelFrame: panel, wasPlaying: wasPlaying
    )
}

private func morphOf(_ plan: PanelPlan) -> PanelPlan.Morph? {
    if case .morph(let morph) = plan { morph } else { nil }
}

@Test func aNotchDrawnAlreadyIsKept() {
    #expect(plan(shown: (.expanded, large), panel: large) == .keep)
}

@Test func aChangeOfPlaybackAloneRedraws() {
    #expect(plan(playing: false, shown: (.expanded, large), panel: large) != .keep)
}

@Test func aStateWithNoFrameDrawsNothingWhenNothingIsShown() {
    #expect(plan(.hidden, target: nil) == .keep)
}

@Test func hidingASlidesTheWingsBackWhenAnimated() {
    #expect(plan(.hidden, target: nil, shown: (.expanded, large), panel: large) == .hide(animated: true))
}

@Test func hidingIsAtOnceWhenNotAnimatedOrWithoutAPanel() {
    #expect(plan(.hidden, target: nil, animated: false, shown: (.expanded, large), panel: large) == .hide(animated: false))
    #expect(plan(.hidden, target: nil, shown: (.expanded, large), panel: nil) == .hide(animated: false))
}

@Test func aFirstAnimatedDrawOpensHiddenOverTheHousing() throws {
    let morph = try #require(morphOf(plan(.resting, target: small)))
    #expect(morph.opening == small)
    #expect(morph.animated)
    #expect(morph.grow == nil)
    #expect(morph.settle == nil)
}

@Test func aFirstDrawKeepsTheLargerPanelOfAHideStillSliding() throws {
    let morph = try #require(morphOf(plan(.resting, target: small, panel: large)))
    #expect(morph.opening == large)
    #expect(morph.settle == small)
}

@Test func openingGrowsThePanelBeforeTheShape() throws {
    let morph = try #require(morphOf(plan(.expanded, target: large, shown: (.resting, small), panel: small)))
    #expect(morph.opening == nil)
    #expect(morph.grow == large)
    #expect(morph.animated)
    #expect(morph.settle == nil)
}

@Test func aTargetThatMovesGrowsThePanelToCoverBothAndSettlesOnTheTarget() throws {
    let moved = small.offsetBy(dx: 400, dy: 0)
    let morph = try #require(morphOf(plan(.resting, target: moved, shown: (.resting, small), panel: small)))
    #expect(morph.grow == small.union(moved))
    #expect(morph.settle == moved)
}

@Test func closingKeepsThePanelUntilTheShapeHasShrunk() throws {
    let morph = try #require(morphOf(plan(.resting, target: small, shown: (.expanded, large), panel: large)))
    #expect(morph.grow == nil)
    #expect(morph.settle == small)
}

@Test func aPanelThatAlreadyHasTheTargetNeedsNoSettling() throws {
    let morph = try #require(morphOf(plan(.resting, target: small, shown: (.note, small), panel: small, wasPlaying: false)))
    #expect(morph.grow == nil)
    #expect(morph.settle == nil)
}

@Test func withoutAnimationThePanelTakesTheTargetAtOnce() throws {
    let morph = try #require(morphOf(plan(animated: false, shown: (.resting, small), panel: small)))
    #expect(!morph.animated)
    #expect(morph.opening == nil)
    #expect(morph.grow == nil)
    #expect(morph.settle == nil)
}

@Test func withoutAnimationAFirstDrawDoesNotOpenHidden() throws {
    let morph = try #require(morphOf(plan(animated: false)))
    #expect(!morph.animated)
    #expect(morph.opening == nil)
}
