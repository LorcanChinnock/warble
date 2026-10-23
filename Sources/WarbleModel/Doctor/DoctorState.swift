import Foundation

/// The Doctor's checks for every notch, and the "!" they put on it when one fails. It checks again only when something
/// changes: the adapter stops, a player opens or quits, macOS refuses a script, or a notch opens. While the adapter
/// works every check passes without asking macOS anything.
public struct DoctorState: Feature {
    /// The adapter as the app last saw it. Anything but `.working` follows players opening and quitting.
    public internal(set) var adapter = Doctor.Adapter.working
    public internal(set) var checks: [Doctor.Check]
    /// The failures the user put off with Not now, until Warble opens again or another check fails.
    public internal(set) var dismissed: Set<Doctor.Kind> = []
    /// Bumped by every refresh, so facts that arrive after a later refresh has begun are dropped.
    public internal(set) var refreshes = 0

    public var needsAttention: Bool {
        Doctor.needsAttention(checks, dismissed: dismissed)
    }

    init(checks: [Doctor.Check]) {
        self.checks = checks
    }

    var deadline: Date? { nil }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .adapterChanged(let latest):
            guard latest != adapter else { return [] }
            let followed = adapter != .working
            adapter = latest
            var effects: [AppEffect] = []
            if (latest != .working) != followed {
                effects.append(.followPlayers(latest != .working))
            }
            effects.append(refresh())
            return effects
        case .factsGathered(let facts, let pass):
            guard pass == refreshes else { return [] }
            update(Doctor.checks(facts))
        case .playersChanged, .automationDenied:
            return [refresh()]
        case .fallbackReported:
            // Only while Automation fails, so a player that plays after the user allowed it clears the "!" without asking
            // macOS on every change of track.
            if checks.contains(where: { $0.kind == .automation && $0.outcome == .fail }) {
                return [refresh()]
            }
        case .notNow:
            dismissed.formUnion(checks.filter { $0.outcome == .fail }.map(\.kind))
        default:
            break
        }
        return []
    }

    /// Gathers the facts again. While the adapter works no check needs macOS, so the facts take no work.
    mutating func refresh() -> AppEffect {
        refreshes += 1
        return .gatherFacts(adapter, pass: refreshes)
    }

    private mutating func update(_ latest: [Doctor.Check]) {
        guard latest != checks else { return }
        // A check that passes again can fail again later, and then it needs the "!".
        dismissed.subtract(latest.filter { $0.outcome != .fail }.map(\.kind))
        checks = latest
    }
}
