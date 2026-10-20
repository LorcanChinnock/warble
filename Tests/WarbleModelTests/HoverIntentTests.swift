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

@Test func stayingOnTheNotchExpandsAfter250Milliseconds() {
    var hovering = intent((.pointerEntered, 0))
    #expect(hovering.deadline == entered + 0.25)
    hovering.advance(to: entered + 0.249)
    #expect(hovering.state == .resting)
    hovering.advance(to: entered + 0.25)
    #expect(hovering.state == .expanded)
    #expect(hovering.deadline == nil)
}

@Test func aPointerThatLeavesJustBeforeTheDelayNeverOpensTheNotch() {
    var crossing = intent((.pointerEntered, 0), (.pointerLeft, 0.2))
    #expect(crossing.deadline == nil)
    crossing.advance(to: entered + 5)
    #expect(crossing.state == .resting)
}

@Test func comingBackToTheNotchWaitsTheFullDelayAgain() {
    var back = intent((.pointerEntered, 0), (.pointerLeft, 0.2), (.pointerEntered, 0.3))
    #expect(back.deadline == entered + 0.55)
    back.advance(to: entered + 0.549)
    #expect(back.state == .resting)
    back.advance(to: entered + 0.55)
    #expect(back.state == .expanded)
}

@Test func aLateTimerStillOpensTheNotch() {
    var hovering = intent((.pointerEntered, 0))
    hovering.advance(to: entered + 2)
    #expect(hovering.state == .expanded)
    #expect(hovering.deadline == nil)
}

@Test func aClickExpandsWithoutWaitingForTheDelay() {
    let clicked = intent((.pointerEntered, 0), (.click, 0.03))
    #expect(clicked.state == .expanded)
    #expect(clicked.deadline == nil)
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

@Test func aLateTimerAfterLeavingTheHoveredNotchClosesItAgain() {
    var leaving = intent((.pointerEntered, 0), (.pointerLeft, 1))
    #expect(leaving.state == .expanded)
    #expect(leaving.deadline == entered + 1.4)
    leaving.advance(to: entered + 5)
    #expect(leaving.state == .resting)
    #expect(leaving.deadline == nil)
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
    #expect(dismissed.deadline == entered + 7.25)
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

@Test func anOpenMenuKeepsTheCardOpenWhileThePointerIsOnIt() {
    var open = intent((.pointerEntered, 0), (.menuOpened, 1), (.pointerLeft, 1.1))
    #expect(open.deadline == nil)
    open.advance(to: entered + 10)
    #expect(open.state == .expanded)
}

@Test func aClickOutsideWhileAMenuIsOpenLeavesTheCardOpen() {
    let open = intent((.click, 0), (.menuOpened, 1), (.dismiss, 2))
    #expect(open.state == .expanded)
}

@Test func theCardClosesAfterTheMenuWithThePointerAway() {
    var closing = intent((.pointerEntered, 0), (.menuOpened, 1), (.pointerLeft, 1.1), (.menuClosed, 5))
    #expect(closing.deadline == entered + 5.4)
    closing.advance(to: entered + 5.4)
    #expect(closing.state == .resting)
}

@Test func theCardStaysOpenAfterTheMenuWithThePointerOnIt() {
    let open = intent((.pointerEntered, 0), (.menuOpened, 1), (.menuClosed, 2))
    #expect(open.state == .expanded)
    #expect(open.deadline == nil)
}

/// What a notch shows for `intent` with nothing playing and nothing wrong.
private func idleState(_ intent: HoverIntent, idleHover: IdleHover = .lastPlayed) -> NotchState {
    NotchState(intent.state, isPlaying: false, needsAttention: false, idleHover: idleHover)
}

@Test func theIdleNotchRestsBehindTheHousing() {
    #expect(idleState(HoverIntent()) == .idle)
}

@Test func stayingOnTheIdleHousingOpensTheIdleCardAfter250Milliseconds() {
    var hovering = intent((.pointerEntered, 0))
    #expect(hovering.deadline == entered + 0.25)
    hovering.advance(to: entered + 0.249)
    #expect(idleState(hovering) == .idle)
    hovering.advance(to: entered + 0.25)
    #expect(idleState(hovering) == .expanded)
    #expect(NotchCard(isPlaying: false, needsAttention: false, showsDoctor: false) == .idle)
}

@Test func aPointerCrossingTheIdleHousingOpensNothing() {
    var crossing = intent((.pointerEntered, 0), (.pointerLeft, 0.05))
    crossing.advance(to: entered + 5)
    #expect(idleState(crossing) == .idle)
}

@Test func clickingTheIdleHousingOpensTheIdleCardAtOnce() {
    #expect(idleState(intent((.pointerEntered, 0), (.click, 0.03))) == .expanded)
}

@Test func theIdleCardClosesBehindTheHousingWhenThePointerLeaves() {
    var leaving = intent((.pointerEntered, 0), (.pointerLeft, 1))
    leaving.advance(to: entered + 1.4)
    #expect(idleState(leaving) == .idle)
}

@Test func withIdleHoverOffTheIdleHousingDrawsNothingAndNeverOpens() {
    var hovering = intent((.pointerEntered, 0), (.click, 0.1))
    hovering.advance(to: entered + 5)
    #expect(idleState(HoverIntent(), idleHover: .nothing) == .hidden)
    #expect(idleState(hovering, idleHover: .nothing) == .hidden)
}

@Test func playbackStoppingUnderAnOpenCardLeavesTheIdleCardOpen() {
    let open = intent((.pointerEntered, 0), (.click, 0.1))
    #expect(NotchState(open.state, isPlaying: true, needsAttention: false, idleHover: .lastPlayed) == .expanded)
    #expect(idleState(open) == .expanded)
    #expect(NotchCard(isPlaying: true, needsAttention: false, showsDoctor: false) == .player)
}

@Test func withACheckFailedTheIdleNotchRestsWithTheExclamationAndOpensOnTheChecks() {
    for idleHover in IdleHover.allCases {
        #expect(NotchState(HoverIntent().state, isPlaying: false, needsAttention: true, idleHover: idleHover) == .resting)
    }
    #expect(NotchCard(isPlaying: false, needsAttention: true, showsDoctor: false) == .doctor)
    #expect(NotchCard(isPlaying: true, needsAttention: true, showsDoctor: false) == .player)
    #expect(NotchCard(isPlaying: true, needsAttention: true, showsDoctor: true) == .doctor)
}
