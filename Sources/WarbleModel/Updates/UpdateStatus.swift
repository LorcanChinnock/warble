import Foundation

/// What the last update check in this session found. Sparkle keeps no result between launches, so a new launch starts
/// with none.
public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case found(version: String)
    /// The check didn't reach the update server, or the server's answer couldn't be read.
    case failed
}

/// What Settings › About says about updates, on the status line under the version. It says "Up to date" only when a
/// check in this session found nothing, since otherwise a release may have come out since the last check.
public enum UpdateStatus: Equatable, Sendable {
    /// The build has no update feed, as WarbleDev and local builds don't, so it never checks.
    case off
    /// A check is running, whether the person asked for it or it was scheduled.
    case checking
    /// A check found this version, and it isn't installed yet.
    case available(version: String)
    /// A check in this session found nothing newer, at this time.
    case upToDate(checked: Date?)
    /// The last check in this session failed.
    case failed
    /// No check has finished in this session; the last one, in an earlier session, was at this time.
    case lastChecked(Date)
    /// Warble has never checked.
    case notChecked

    /// - Parameters:
    ///   - hasFeed: Whether the build can update itself.
    ///   - isChecking: Whether a check is running now.
    ///   - pendingVersion: A version an automatic check found that the person hasn't looked at yet.
    ///   - lastResult: What the last check in this session found.
    ///   - lastCheck: When Warble last checked, in this session or an earlier one.
    public init(hasFeed: Bool, isChecking: Bool, pendingVersion: String?, lastResult: UpdateCheckResult?, lastCheck: Date?) {
        guard hasFeed else {
            self = .off
            return
        }
        if isChecking {
            self = .checking
            return
        }
        if let pendingVersion {
            self = .available(version: pendingVersion)
            return
        }
        switch lastResult {
        case .found(let version):
            self = .available(version: version)
        case .upToDate:
            self = .upToDate(checked: lastCheck)
        case .failed:
            self = .failed
        case nil:
            self = lastCheck.map { .lastChecked($0) } ?? .notChecked
        }
    }

    /// The version a check found, if one did.
    public var availableVersion: String? {
        if case .available(let version) = self {
            return version
        }
        return nil
    }
}

/// How a check's time reads on the status line: "today at 09:12", "yesterday at 09:12", or the date alone.
public enum CheckDay: Equatable, Sendable {
    case today
    case yesterday
    case earlier

    public init(_ date: Date, now: Date, calendar: Calendar) {
        if calendar.isDate(date, inSameDayAs: now) {
            self = .today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            self = .yesterday
        } else {
            self = .earlier
        }
    }
}

/// What About's two update switches show. Both are off and dimmed in a build with no feed. Installing automatically
/// needs automatic checks, so it shows off and dimmed while they're off, whatever Sparkle has stored for it.
public struct UpdateSwitches: Equatable, Sendable {
    public var checks: Bool
    public var canChangeChecks: Bool
    public var installs: Bool
    public var canChangeInstalls: Bool
}

extension UpdateSwitches {
    /// - Parameters:
    ///   - hasFeed: Whether the build can update itself.
    ///   - checksAutomatically: Sparkle's `automaticallyChecksForUpdates`.
    ///   - downloadsAutomatically: Sparkle's `automaticallyDownloadsUpdates`.
    public init(hasFeed: Bool, checksAutomatically: Bool, downloadsAutomatically: Bool) {
        canChangeChecks = hasFeed
        checks = hasFeed && checksAutomatically
        canChangeInstalls = checks
        installs = checks && downloadsAutomatically
    }
}
