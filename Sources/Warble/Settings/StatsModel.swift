import Foundation
import WarbleCore

/// The last week of listening as Settings draws it, kept from `AppState`, and what its buttons ask for.
@MainActor
@Observable
final class StatsModel {
    private(set) var summary: WeeklySummary?

    @ObservationIgnored private let dispatch: (AppAction) -> Void

    init(dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
    }

    func apply(_ summary: WeeklySummary?) {
        if summary != self.summary {
            self.summary = summary
        }
    }

    /// Reads the week from disk, and the summary arrives through `apply`.
    func refresh() {
        dispatch(.refreshStats)
    }

    func clear() {
        dispatch(.clearStats)
    }
}

enum StatsFormat {
    /// How long, to the minute: "3 hr, 12 min", or "Less than a minute".
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return String(localized: "Less than a minute") }
        return Duration.seconds(seconds.rounded(.down)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
