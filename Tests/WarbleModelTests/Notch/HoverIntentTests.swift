import Foundation
import Testing
@testable import WarbleModel

private let entered = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func intent(_ events: (HoverEvent, TimeInterval)...) -> HoverIntent {
    var intent = HoverIntent()
    for (event, offset) in events {
        intent.handle(event, at: entered + offset)
    }
    return intent
}

@Test func theNotchStartsRestingWithNothingDue() {
    let intent = HoverIntent()
    #expect(intent.state == .resting)
    #expect(intent.deadline == nil)
}

@Test func aPointerCrossingTheNotchToAMenuBarItemNeverOpensIt() {
    var crossing = intent((.pointerEntered, 0), (.pointerLeft, 0.05))
    #expect(crossing.deadline == nil)
    crossing.advance(to: entered + 5)
    #expect(crossing.state == .resting)
}

@Test func stayingOnTheNotchExpandsAfter80Milliseconds() {
    var hovering = intent((.pointerEntered, 0))
    #expect(hovering.deadline == entered + 0.08)
    hovering.advance(to: entered + 0.079)
    #expect(hovering.state == .resting)
    hovering.advance(to: entered + 0.08)
    #expect(hovering.state == .expanded)
    #expect(hovering.deadline == nil)
}

@Test func aPointerThatLeavesJustBeforeTheDelayNeverOpensTheNotch() {
    var crossing = intent((.pointerEntered, 0), (.pointerLeft, 0.05))
    #expect(crossing.deadline == nil)
    crossing.advance(to: entered + 5)
    #expect(crossing.state == .resting)
}

@Test func comingBackToTheNotchWaitsTheFullDelayAgain() {
    var back = intent((.pointerEntered, 0), (.pointerLeft, 0.05), (.pointerEntered, 0.4))
    #expect(back.deadline == entered + 0.48)
    back.advance(to: entered + 0.479)
    #expect(back.state == .resting)
    back.advance(to: entered + 0.48)
    #expect(back.state == .expanded)
}

@Test func aLateTimerStillOpensTheNotch() {
    var hovering = intent((.pointerEntered, 0))
    hovering.advance(to: entered + 2)
    #expect(hovering.state == .expanded)
    #expect(hovering.deadline == nil)
}

@Test func leavingTheExpandedNotchClosesIt150MillisecondsLater() {
    var leaving = intent((.pointerEntered, 0), (.pointerEntered, 0.2), (.pointerLeft, 2))
    #expect(leaving.state == .expanded)
    #expect(leaving.deadline == entered + 2.15)
    leaving.advance(to: entered + 2.149)
    #expect(leaving.state == .expanded)
    leaving.advance(to: entered + 2.15)
    #expect(leaving.state == .resting)
    #expect(leaving.deadline == nil)
}

@Test func comingBackBeforeItClosesKeepsTheNotchOpen() {
    var back = intent((.pointerEntered, 0), (.pointerEntered, 0.2), (.pointerLeft, 2), (.pointerEntered, 2.1))
    #expect(back.deadline == nil)
    back.advance(to: entered + 5)
    #expect(back.state == .expanded)
}

@Test func aLateTimerAfterLeavingTheHoveredNotchClosesItAgain() {
    var leaving = intent((.pointerEntered, 0), (.pointerLeft, 1))
    #expect(leaving.state == .expanded)
    #expect(leaving.deadline == entered + 1.15)
    leaving.advance(to: entered + 5)
    #expect(leaving.state == .resting)
    #expect(leaving.deadline == nil)
}

@Test func dismissingClosesTheNotchAtOnce() {
    let dismissed = intent((.pointerEntered, 0), (.dismiss, 2))
    #expect(dismissed.state == .resting)
    #expect(dismissed.deadline == nil)
}

@Test func afterDismissingThePointerHasToLeaveAndComeBackToOpenTheNotch() {
    var dismissed = intent((.pointerEntered, 0), (.pointerEntered, 0.2), (.dismiss, 1))
    dismissed.advance(to: entered + 5)
    #expect(dismissed.state == .resting)
    dismissed.handle(.pointerLeft, at: entered + 6)
    dismissed.handle(.pointerEntered, at: entered + 7)
    #expect(dismissed.deadline == entered + 7.08)
}

@Test func anOpenMenuKeepsTheCardOpenWhileThePointerIsOnIt() {
    var open = intent((.pointerEntered, 0), (.menuOpened, 1), (.pointerLeft, 1.1))
    #expect(open.deadline == nil)
    open.advance(to: entered + 10)
    #expect(open.state == .expanded)
}

@Test func aClickOutsideWhileAMenuIsOpenLeavesTheCardOpen() {
    let open = intent((.pointerEntered, 0), (.menuOpened, 1), (.dismiss, 2))
    #expect(open.state == .expanded)
}

@Test func theCardClosesAfterTheMenuWithThePointerAway() {
    var closing = intent((.pointerEntered, 0), (.menuOpened, 1), (.pointerLeft, 1.1), (.menuClosed, 5))
    #expect(closing.deadline == entered + 5.15)
    closing.advance(to: entered + 5.15)
    #expect(closing.state == .resting)
}

@Test func theCardStaysOpenAfterTheMenuWithThePointerOnIt() {
    let open = intent((.pointerEntered, 0), (.menuOpened, 1), (.menuClosed, 2))
    #expect(open.state == .expanded)
    #expect(open.deadline == nil)
}

@Test func aRightClickMenuOnARestingNotchKeepsItResting() {
    var resting = intent((.pointerEntered, 0), (.menuOpened, 0.05))
    #expect(resting.deadline == nil)
    resting.advance(to: entered + 10)
    #expect(resting.state == .resting)
}

@Test func aRestingNotchStaysRestingAfterItsMenuCloses() {
    var resting = intent((.pointerEntered, 0), (.menuOpened, 0.05), (.menuClosed, 3))
    #expect(resting.deadline == nil)
    resting.advance(to: entered + 10)
    #expect(resting.state == .resting)
}

@Test func aRestingNotchOpensAgainOnceThePointerComesBackAfterItsMenu() {
    var back = intent((.pointerEntered, 0), (.menuOpened, 0.05), (.menuClosed, 3), (.pointerLeft, 4), (.pointerEntered, 5))
    #expect(back.deadline == entered + 5.08)
    back.advance(to: entered + 5.08)
    #expect(back.state == .expanded)
}

@Test func withNothingPlayingTheNotchIsHiddenWhateverTheHover() {
    #expect(NotchState(HoverIntent().state, isPlaying: false) == .hidden)
    #expect(NotchState(intent((.pointerEntered, 0), (.pointerEntered, 0.2)).state, isPlaying: false) == .hidden)
}

@Test func playbackStoppingUnderAnOpenNotchClosesIt() {
    let open = intent((.pointerEntered, 0), (.pointerEntered, 0.2))
    #expect(NotchState(open.state, isPlaying: true) == .expanded)
    #expect(NotchState(open.state, isPlaying: false) == .hidden)
}

@Test func aCardWithSomethingToReadStaysOpenAfterTheMenuClosesUntilItsTime() {
    var open = intent((.pointerEntered, 0), (.menuOpened, 1), (.pointerLeft, 1.1), (.menuClosed, 5), (.keepOpen(until: entered + 9), 5.1))
    #expect(open.deadline == entered + 9)
    open.advance(to: entered + 8.9)
    #expect(open.state == .expanded)
    open.advance(to: entered + 9)
    #expect(open.state == .resting)
}

@Test func aCardKeptOpenStillClosesAfterTheDelayOncePastItsTime() {
    var open = intent((.pointerEntered, 0), (.keepOpen(until: entered + 2), 1), (.pointerLeft, 5))
    #expect(open.deadline == entered + 5.15)
    open.advance(to: entered + 5.15)
    #expect(open.state == .resting)
}

@Test func aRestingNotchIgnoresBeingKeptOpen() {
    let resting = intent((.keepOpen(until: entered + 9), 0))
    #expect(resting.deadline == nil)
    #expect(resting.state == .resting)
}
