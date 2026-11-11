import Foundation
import Testing
@testable import WarbleModel

private let earlier = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func status(hasFeed: Bool = true, checking: Bool = false, pending: String? = nil, result: UpdateCheckResult? = nil, lastCheck: Date? = nil) -> UpdateStatus {
    UpdateStatus(hasFeed: hasFeed, isChecking: checking, pendingVersion: pending, lastResult: result, lastCheck: lastCheck)
}

@Test func aBuildWithNoFeedSaysItDoesntUpdateWhateverElseIsTrue() {
    #expect(status(hasFeed: false, checking: true, pending: "0.2.0", result: .found(version: "0.2.0"), lastCheck: earlier) == .off)
}

@Test func aRunningCheckShowsAsCheckingEvenWithAnUpdateWaiting() {
    #expect(status(checking: true, pending: "0.2.0") == .checking)
    #expect(status(checking: true, result: .failed) == .checking)
}

@Test func anUpdateAScheduledCheckFoundIsReady() {
    #expect(status(pending: "0.2.0", result: .upToDate, lastCheck: earlier) == .available(version: "0.2.0"))
    #expect(status(pending: "0.2.0").availableVersion == "0.2.0")
}

@Test func anUpdateACheckInThisSessionFoundIsReady() {
    #expect(status(result: .found(version: "0.2.0"), lastCheck: earlier) == .available(version: "0.2.0"))
}

@Test func upToDateNeedsACheckInThisSessionThatFoundNothing() {
    #expect(status(result: .upToDate, lastCheck: earlier) == .upToDate(checked: earlier))
    #expect(status(lastCheck: earlier) == .lastChecked(earlier))
    #expect(status(lastCheck: earlier).availableVersion == nil)
}

@Test func aFailedCheckSaysSoUntilTheNextCheckFinishes() {
    #expect(status(result: .failed, lastCheck: earlier) == .failed)
}

@Test func aBuildThatHasNeverCheckedSaysNotChecked() {
    #expect(status() == .notChecked)
}

@Test func aCheckDayIsTodayYesterdayOrEarlierInTheCalendarsTimeZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 0, minute: 30)))
    #expect(CheckDay(now.addingTimeInterval(20 * 60), now: now, calendar: calendar) == .today)
    #expect(CheckDay(now.addingTimeInterval(-20 * 60), now: now, calendar: calendar) == .today)
    #expect(CheckDay(now.addingTimeInterval(-40 * 60), now: now, calendar: calendar) == .yesterday)
    #expect(CheckDay(now.addingTimeInterval(-23 * 3600), now: now, calendar: calendar) == .yesterday)
    #expect(CheckDay(now.addingTimeInterval(-25 * 3600), now: now, calendar: calendar) == .earlier)
}

@Test func bothUpdateSwitchesAreOffAndDimmedWithoutAFeed() {
    let switches = UpdateSwitches(hasFeed: false, checksAutomatically: true, downloadsAutomatically: true)
    #expect(switches == UpdateSwitches(checks: false, canChangeChecks: false, installs: false, canChangeInstalls: false))
}

@Test func installingAutomaticallyIsOffAndDimmedWhileCheckingAutomaticallyIsOff() {
    let switches = UpdateSwitches(hasFeed: true, checksAutomatically: false, downloadsAutomatically: true)
    #expect(switches == UpdateSwitches(checks: false, canChangeChecks: true, installs: false, canChangeInstalls: false))
}

@Test func installingAutomaticallyFollowsSparkleOnceCheckingAutomaticallyIsOn() {
    #expect(UpdateSwitches(hasFeed: true, checksAutomatically: true, downloadsAutomatically: false)
        == UpdateSwitches(checks: true, canChangeChecks: true, installs: false, canChangeInstalls: true))
    #expect(UpdateSwitches(hasFeed: true, checksAutomatically: true, downloadsAutomatically: true)
        == UpdateSwitches(checks: true, canChangeChecks: true, installs: true, canChangeInstalls: true))
}
