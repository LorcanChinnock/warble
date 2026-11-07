import Foundation
import Testing
@testable import WarbleCore

/// Waits until `condition` holds, checking every 10 ms, for up to `limit`. A busy CI runner can run a timer hundreds of
/// milliseconds late, so a test that expects a timer to fire waits for it rather than sleeping a fixed time.
@MainActor
private func waitUntil(limit: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + limit
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
@Test func aTimerFiresOnceAtItsDeadline() async throws {
    let scheduler = TimerScheduler()
    var fired = 0
    scheduler.schedule(at: .now.addingTimeInterval(0.05)) { fired += 1 }
    try await waitUntil { fired > 0 }
    try await Task.sleep(for: .milliseconds(100))
    #expect(fired == 1)
}

@MainActor
@Test func aLaterScheduleReplacesTheEarlierOne() async throws {
    let scheduler = TimerScheduler()
    var fired: [String] = []
    scheduler.schedule(at: .now.addingTimeInterval(0.05)) { fired.append("first") }
    scheduler.schedule(at: .now.addingTimeInterval(0.1)) { fired.append("second") }
    // The first deadline is earlier, so if it hadn't been replaced it would have fired before the second.
    try await waitUntil { fired.contains("second") }
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
    try await waitUntil { fired > 0 }
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
    try await waitUntil { fired == 2 }
    #expect(fired == 2)
}

@Test func theSystemClockReadsTheWallClock() {
    let before = Date.now
    let now = SystemClock().now
    #expect(now >= before)
    #expect(now.timeIntervalSince(before) < 5)
}
