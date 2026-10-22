import Foundation
@testable import WarbleModel

/// A clock that stays where a test puts it.
final class FakeClock: WallClock, @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Records what it's asked to schedule and fires it only when a test says so.
@MainActor
final class FakeScheduler: Scheduler {
    private(set) var deadline: Date?
    /// How many times a deadline was armed, not counting cancels.
    private(set) var armed = 0
    private var fire: (@MainActor () -> Void)?

    func schedule(at deadline: Date?, _ fire: @escaping @MainActor () -> Void) {
        self.deadline = deadline
        self.fire = deadline == nil ? nil : fire
        if deadline != nil {
            armed += 1
        }
    }

    /// Runs the callback scheduled now, as its timer would.
    func run() {
        let fire = fire
        self.fire = nil
        deadline = nil
        fire?()
    }
}
