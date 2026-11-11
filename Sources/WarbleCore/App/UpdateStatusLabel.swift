import Foundation
import WarbleModel

public extension UpdateStatus {
    /// The status line under the version in Settings › About, or nil when there's nothing to say: Warble has never
    /// checked, and the Check for Updates… button beside it says the rest.
    func label(now: Date = .now, calendar: Calendar = .current) -> String? {
        switch self {
        case .off:
            return String(localized: "This build doesn't update itself.")
        case .checking:
            return String(localized: "Checking for updates…")
        case .available(let version):
            return String(localized: "Version \(version) is ready")
        case .failed:
            return String(localized: "Couldn't reach the update server. Check your connection.")
        case .upToDate(let checked):
            guard let checked else {
                return String(localized: "Up to date")
            }
            let time = checked.formatted(date: .omitted, time: .shortened)
            switch CheckDay(checked, now: now, calendar: calendar) {
            case .today:
                return String(localized: "Up to date · checked today at \(time)")
            case .yesterday:
                return String(localized: "Up to date · checked yesterday at \(time)")
            case .earlier:
                return String(localized: "Up to date · checked \(checked.formatted(date: .abbreviated, time: .omitted))")
            }
        case .lastChecked(let checked):
            let time = checked.formatted(date: .omitted, time: .shortened)
            switch CheckDay(checked, now: now, calendar: calendar) {
            case .today:
                return String(localized: "Last checked today at \(time)")
            case .yesterday:
                return String(localized: "Last checked yesterday at \(time)")
            case .earlier:
                return String(localized: "Last checked \(checked.formatted(date: .abbreviated, time: .omitted))")
            }
        case .notChecked:
            return nil
        }
    }
}
