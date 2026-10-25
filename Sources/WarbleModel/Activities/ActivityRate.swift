import Foundation

/// Counts the lines one connection sends, so a runaway sender is told to slow down. It's measured from each line's arrival
/// time, with no timer.
struct ActivityRate: Equatable, Sendable {
    private var arrivals: [Date] = []

    /// Whether a line arriving at `now` is within `ActivityLimits.linesPerSecond` for the second before it.
    mutating func allow(at now: Date) -> Bool {
        arrivals.removeAll { now.timeIntervalSince($0) >= 1 }
        guard arrivals.count < ActivityLimits.linesPerSecond else { return false }
        arrivals.append(now)
        return true
    }
}
