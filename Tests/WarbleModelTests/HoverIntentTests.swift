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

@Test func stayingOnTheNotchPeeksAfter120Milliseconds() {
    var hovering = intent((.pointerEntered, 0))
    #expect(hovering.deadline == entered + 0.12)
    hovering.advance(to: entered + 0.119)
    #expect(hovering.state == .resting)
    hovering.advance(to: entered + 0.12)
    #expect(hovering.state == .peeking)
}

@Test func stayingLongerExpands600MillisecondsAfterEntering() {
    var hovering = intent((.pointerEntered, 0))
    hovering.advance(to: entered + 0.12)
    #expect(hovering.deadline == entered + 0.6)
    hovering.advance(to: entered + 0.6)
    #expect(hovering.state == .expanded)
    #expect(hovering.deadline == nil)
}

@Test func aLateTimerAppliesEveryDeadlineThatPassed() {
    var hovering = intent((.pointerEntered, 0))
    hovering.advance(to: entered + 2)
    #expect(hovering.state == .expanded)
}

@Test func aClickExpandsWithoutWaitingToPeek() {
    let clicked = intent((.pointerEntered, 0), (.click, 0.03))
    #expect(clicked.state == .expanded)
    #expect(clicked.deadline == nil)
}

@Test func aClickWhilePeekingExpands() {
    #expect(intent((.pointerEntered, 0), (.click, 0.3)).state == .expanded)
}

@Test func leavingTheExpandedNotchClosesIt400MillisecondsLater() {
    var leaving = intent((.pointerEntered, 0), (.click, 0.1), (.pointerLeft, 2))
    #expect(leaving.state == .expanded)
    #expect(leaving.deadline == entered + 2.4)
    leaving.advance(to: entered + 2.399)
    #expect(leaving.state == .expanded)
    leaving.advance(to: entered + 2.4)
    #expect(leaving.state == .resting)
    #expect(leaving.deadline == nil)
}

@Test func comingBackBeforeItClosesKeepsTheNotchOpen() {
    var back = intent((.pointerEntered, 0), (.click, 0.1), (.pointerLeft, 2), (.pointerEntered, 2.2))
    #expect(back.deadline == nil)
    back.advance(to: entered + 5)
    #expect(back.state == .expanded)
}

@Test func leavingAPeekClosesIt400MillisecondsLater() {
    var leaving = intent((.pointerEntered, 0), (.pointerLeft, 0.25))
    #expect(leaving.state == .peeking)
    #expect(leaving.deadline == entered + 0.65)
    leaving.advance(to: entered + 0.65)
    #expect(leaving.state == .resting)
}

@Test func comingBackToAPeekWaitsTheFullTimeAgainBeforeExpanding() {
    var back = intent((.pointerEntered, 0), (.pointerLeft, 0.25), (.pointerEntered, 0.5))
    #expect(back.state == .peeking)
    #expect(back.deadline == entered + 1.1)
    back.advance(to: entered + 1.1)
    #expect(back.state == .expanded)
}

@Test func aClickInsideTheExpandedNotchPinsIt() {
    var pinned = intent((.pointerEntered, 0), (.click, 0.1), (.click, 1), (.pointerLeft, 2))
    #expect(pinned.state == .pinned)
    #expect(pinned.deadline == nil)
    pinned.advance(to: entered + 60)
    #expect(pinned.state == .pinned)
}

@Test func moreClicksLeaveTheNotchPinned() {
    #expect(intent((.pointerEntered, 0), (.click, 0.1), (.click, 1), (.click, 2)).state == .pinned)
}

@Test func thePinButtonPinsAndUnpins() {
    var pinned = intent((.pointerEntered, 0), (.click, 0.1), (.pinButton, 1))
    #expect(pinned.state == .pinned)
    pinned.handle(.pinButton, at: entered + 2)
    #expect(pinned.state == .expanded)
    #expect(pinned.deadline == nil)
}

@Test func unpinningWithThePointerAwayClosesIt400MillisecondsLater() {
    var unpinned = intent((.pointerEntered, 0), (.click, 0.1), (.pinButton, 1), (.pointerLeft, 2), (.pinButton, 10))
    #expect(unpinned.state == .expanded)
    #expect(unpinned.deadline == entered + 10.4)
    unpinned.advance(to: entered + 10.4)
    #expect(unpinned.state == .resting)
}

@Test func dismissingClosesTheNotchAtOnceEvenWhenPinned() {
    let dismissed = intent((.pointerEntered, 0), (.click, 0.1), (.click, 1), (.dismiss, 2))
    #expect(dismissed.state == .resting)
    #expect(dismissed.deadline == nil)
}

@Test func afterDismissingThePointerHasToLeaveAndComeBackToOpenTheNotch() {
    var dismissed = intent((.pointerEntered, 0), (.click, 0.1), (.dismiss, 1))
    dismissed.advance(to: entered + 5)
    #expect(dismissed.state == .resting)
    dismissed.handle(.pointerLeft, at: entered + 6)
    dismissed.handle(.pointerEntered, at: entered + 7)
    #expect(dismissed.deadline == entered + 7.12)
}

@Test func aClickAfterDismissingStillClosesWhenThePointerLeaves() {
    var reopened = intent((.pointerEntered, 0), (.click, 0.1), (.dismiss, 1), (.click, 2))
    #expect(reopened.state == .expanded)
    #expect(reopened.deadline == nil)
    reopened.handle(.pointerLeft, at: entered + 3)
    #expect(reopened.deadline == entered + 3.4)
    reopened.advance(to: entered + 3.4)
    #expect(reopened.state == .resting)
}

@Test func unpinningAfterDismissingKnowsThePointerIsStillOnTheNotch() {
    let unpinned = intent((.pointerEntered, 0), (.click, 0.1), (.dismiss, 1), (.click, 2), (.pinButton, 3), (.pinButton, 4))
    #expect(unpinned.state == .expanded)
    #expect(unpinned.deadline == nil)
}
