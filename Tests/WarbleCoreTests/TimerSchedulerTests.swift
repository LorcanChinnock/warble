import Foundation
import Testing
@testable import WarbleCore

@MainActor
@Test func aTimerFiresOnceAtItsDeadline() async throws {
    let scheduler = TimerScheduler()
    var fired = 0
    scheduler.schedule(at: .now.addingTimeInterval(0.05)) { fired += 1 }
    try await Task.sleep(for: .milliseconds(300))
    #expect(fired == 1)
}

@MainActor
@Test func aLaterScheduleReplacesTheEarlierOne() async throws {
    let scheduler = TimerScheduler()
    var fired: [String] = []
    scheduler.schedule(at: .now.addingTimeInterval(0.05)) { fired.append("first") }
    scheduler.schedule(at: .now.addingTimeInterval(0.1)) { fired.append("second") }
    try await Task.sleep(for: .milliseconds(400))
    #expect(fired == ["second"])
}

@MainActor
@Test func noDeadlineCancelsTheTimer() async throws {
    let scheduler = TimerScheduler()
    var fired = 0
    scheduler.schedule(at: .now.addingTimeInterval(0.05)) { fired += 1 }
    scheduler.schedule(at: nil) { fired += 1 }
    try await Task.sleep(for: .milliseconds(300))
    #expect(fired == 0)
}

@MainActor
@Test func aDeadlineInThePastFiresAtOnce() async throws {
    let scheduler = TimerScheduler()
    var fired = 0
    scheduler.schedule(at: .now.addingTimeInterval(-5)) { fired += 1 }
    try await Task.sleep(for: .milliseconds(200))
    #expect(fired == 1)
}

@MainActor
@Test func aFiredTimerCanBeScheduledAgain() async throws {
    let scheduler = TimerScheduler()
    var fired = 0
    scheduler.schedule(at: .now.addingTimeInterval(0.05)) {
        fired += 1
        scheduler.schedule(at: .now.addingTimeInterval(0.05)) { fired += 1 }
    }
    try await Task.sleep(for: .milliseconds(400))
    #expect(fired == 2)
}

@Test func theSystemClockReadsTheWallClock() {
    let before = Date.now
    let now = SystemClock().now
    #expect(now >= before)
    #expect(now.timeIntervalSince(before) < 5)
}
