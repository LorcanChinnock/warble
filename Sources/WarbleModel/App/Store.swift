import Foundation

/// Holds the `AppState`, runs `reduce` for each action synchronously on the main actor, so nothing sits between a
/// hover or a click and what it changes, and keeps one timer armed for the state's deadline, and none without one.
@MainActor
public final class Store {
    public private(set) var state: AppState
    /// Called after each action with the state before and after it, before its effects run.
    public var onChange: (_ old: AppState, _ new: AppState) -> Void = { _, _ in }
    /// Carries out each effect an action returns.
    public var perform: (AppEffect) -> Void = { _ in }

    private let clock: any WallClock
    private let scheduler: any Scheduler
    private var armed: Date?

    public init(state: AppState, clock: any WallClock, scheduler: any Scheduler) {
        self.state = state
        self.clock = clock
        self.scheduler = scheduler
    }

    public func dispatch(_ action: AppAction) {
        dispatch(action, at: clock.now)
    }

    private func dispatch(_ action: AppAction, at now: Date) {
        let old = state
        let effects = reduce(&state, action, now: now)
        arm()
        onChange(old, state)
        effects.forEach(perform)
    }

    /// A timer may fire a moment early, so a tick counts as at its deadline at the earliest.
    private func arm() {
        let deadline = state.deadline
        guard deadline != armed else { return }
        armed = deadline
        scheduler.schedule(at: deadline) { [weak self] in
            guard let self, let deadline else { return }
            self.armed = nil
            self.dispatch(.tick, at: max(self.clock.now, deadline))
        }
    }
}
