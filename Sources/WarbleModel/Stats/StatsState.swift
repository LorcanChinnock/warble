import Foundation

/// The listening stats: whether Settings has them on, the track being counted and the summary Settings shows. With them
/// off nothing is counted or written. It needs no timer: a span is worked out from the time when its track pauses,
/// changes, stops or Warble quits.
struct StatsState: Feature {
    var isOn: Bool
    /// The track being counted, or `nil` when none is or stats are off.
    var session: ListeningSession?
    /// The last week as Settings last asked for it, or `nil` before it has.
    var summary: WeeklySummary?
    /// Set when Warble is quitting, after which nothing starts counting again.
    private var quitting = false

    init(isOn: Bool = false) {
        self.isOn = isOn
    }

    var deadline: Date? { nil }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .statsChanged(let on):
            // Turning them off drops the track under way unwritten, since nothing is kept while they're off.
            isOn = on
            if !on {
                session = nil
            }
        case .refreshStats:
            return [.loadStats(since: now.addingTimeInterval(-WeeklySummary.retention))]
        case .statsLoaded(let spans):
            summary = WeeklySummary(spans, at: now)
        case .clearStats:
            summary = .empty
            // What was playing before is gone too, so the track under way counts from now.
            session?.since = now
            return [.clearStats]
        case .willQuit:
            quitting = true
            guard let ended = session?.span(endingAt: now) else {
                session = nil
                return []
            }
            session = nil
            return [.recordListening(ended)]
        default:
            break
        }
        return []
    }

    /// Ends the span when the track playing changes, and starts the next, once the action and the settle pass are done.
    mutating func follow(_ shared: SharedState, at now: Date) -> [AppEffect] {
        let current = isOn && !quitting ? ListeningSession.Track(shared) : nil
        guard current != session?.track else { return [] }
        var effects: [AppEffect] = []
        if let span = session?.span(endingAt: now) {
            effects.append(.recordListening(span))
        }
        session = current.map { ListeningSession(track: $0, since: now) }
        return effects
    }
}
