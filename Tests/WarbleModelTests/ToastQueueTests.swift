import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func track(_ title: String, duration: TimeInterval = 2) -> Notice<String> {
    Notice(kind: .trackChanged, content: title, duration: duration)
}

private func output(_ name: String, duration: TimeInterval = 3) -> Notice<String> {
    Notice(kind: .outputChanged, content: name, duration: duration)
}

@Test func theQueueStartsEmptyWithNothingDue() {
    let queue = ToastQueue<String>()
    #expect(queue.current == nil)
    #expect(queue.deadline == nil)
}

@Test func aNoticeShowsAtOnceForItsDuration() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    #expect(queue.current == track("One"))
    #expect(queue.deadline == start + 2)
    queue.advance(to: start + 1.9)
    #expect(queue.current == track("One"))
    queue.advance(to: start + 2)
    #expect(queue.current == nil)
    #expect(queue.deadline == nil)
}

@Test func skippingFiveTracksShowsOneToastForTheLast() {
    var queue = ToastQueue<String>()
    for (index, title) in ["One", "Two", "Three", "Four", "Five"].enumerated() {
        queue.post(track(title), at: start + Double(index) * 0.3)
    }
    #expect(queue.current == track("Five"))
    #expect(queue.waiting.isEmpty)
    // The last one gets its full time from when it came.
    #expect(queue.deadline == start + 1.2 + 2)
}

@Test func aNoticeOfAnotherKindWaitsItsTurn() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.post(output("AirPods"), at: start + 0.5)
    #expect(queue.current == track("One"))
    #expect(queue.waiting == [output("AirPods")])
    queue.advance(to: start + 2)
    #expect(queue.current == output("AirPods"))
    #expect(queue.deadline == start + 2 + 3)
    queue.advance(to: start + 5)
    #expect(queue.current == nil)
}

@Test func aWaitingNoticeIsReplacedInPlace() {
    var queue = ToastQueue<String>()
    queue.post(output("AirPods"), at: start)
    queue.post(track("One"), at: start + 0.1)
    queue.post(track("Two"), at: start + 0.2)
    #expect(queue.current == output("AirPods"))
    #expect(queue.waiting == [track("Two")])
}

@Test func theCurrentKindReplacesItEvenWithAnotherWaiting() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.post(output("AirPods"), at: start + 0.5)
    queue.post(track("Two"), at: start + 1)
    #expect(queue.current == track("Two"))
    #expect(queue.deadline == start + 3)
    #expect(queue.waiting == [output("AirPods")])
}

@Test func hoveringKeepsANoticeShowing() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.hold(true, at: start + 1)
    #expect(queue.deadline == nil)
    queue.advance(to: start + 60)
    #expect(queue.current == track("One"))
}

@Test func leavingGivesTheNoticeItsFullTimeAgain() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.hold(true, at: start + 1)
    queue.hold(false, at: start + 10)
    #expect(queue.deadline == start + 12)
    queue.advance(to: start + 12)
    #expect(queue.current == nil)
}

@Test func aReplacementWhileHoveringStaysUntilThePointerLeaves() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.hold(true, at: start + 1)
    queue.post(track("Two"), at: start + 5)
    #expect(queue.current == track("Two"))
    #expect(queue.deadline == nil)
}

@Test func holdingWithNothingShowingHoldsNothingLater() {
    var queue = ToastQueue<String>()
    queue.hold(true, at: start)
    queue.post(track("One"), at: start + 1)
    #expect(queue.deadline == start + 3)
}

@Test func aClickDismissesTheNoticeAndShowsTheNext() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.post(output("AirPods"), at: start)
    queue.hold(true, at: start + 0.5)
    queue.dismiss(at: start + 1)
    #expect(queue.current == output("AirPods"))
    // The pointer was on the one it clicked, so the next runs its own time.
    #expect(queue.deadline == start + 4)
    queue.dismiss(at: start + 2)
    #expect(queue.current == nil)
    #expect(queue.deadline == nil)
}

@Test func aLateTimerSkipsNoticesThatWouldAlreadyHaveGone() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.post(output("AirPods"), at: start)
    queue.advance(to: start + 4)
    #expect(queue.current == output("AirPods"))
    #expect(queue.deadline == start + 5)
    queue.advance(to: start + 60)
    #expect(queue.current == nil)
}

@Test func aPostAfterAMissedDeadlineAppliesItFirst() {
    var queue = ToastQueue<String>()
    queue.post(track("One"), at: start)
    queue.post(output("AirPods"), at: start + 10)
    #expect(queue.current == output("AirPods"))
    #expect(queue.waiting.isEmpty)
}
