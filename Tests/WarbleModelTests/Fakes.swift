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

/// Holds one temporary key, as `HotkeyCenter` does, and presses it when a test says so.
@MainActor
final class FakeHotkeys: HotkeyRegistrar {
    private(set) var temporary: KeyCombo?
    var refuses = false
    private(set) var unregisters = 0
    private var onPress: (() -> Void)?

    func registerTemporary(_ combo: KeyCombo, onPress: @escaping () -> Void) -> Bool {
        guard !refuses else { return false }
        temporary = combo
        self.onPress = onPress
        return true
    }

    func unregisterTemporary() {
        unregisters += 1
        temporary = nil
        onPress = nil
    }

    func press() {
        onPress?()
    }
}

/// Displays a test sets.
@MainActor
final class FakeDisplays: DisplayProvider {
    var displays: [NotchDisplay] = [] {
        didSet { onChange() }
    }
    var onChange: () -> Void = {}
}
