import Foundation

/// The time now. Named so it doesn't hide the standard library's `Clock`.
public protocol WallClock: Sendable {
    var now: Date { get }
}

/// Runs one callback at a time, at a date. Each call replaces the one before, and `nil` cancels it, so the owner holds
/// one timer at most.
@MainActor
public protocol Scheduler: AnyObject {
    func schedule(at deadline: Date?, _ fire: @escaping @MainActor () -> Void)
}
