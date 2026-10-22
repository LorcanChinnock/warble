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

/// Takes one key from every app for a while, such as Escape while a notch is open.
@MainActor
public protocol HotkeyRegistrar: AnyObject {
    /// Replaces any earlier temporary key; false when macOS refused it.
    @discardableResult
    func registerTemporary(_ combo: KeyCombo, onPress: @escaping () -> Void) -> Bool
    func unregisterTemporary()
}

/// The displays connected now, and a call when they change: plugged in or removed, a new resolution, or the lid closing.
@MainActor
public protocol DisplayProvider: AnyObject {
    var displays: [NotchDisplay] { get }
    var onChange: () -> Void { get set }
}

extension DisplayProvider {
    /// The housings the displays connected now call for under `rules`.
    public func housings(rules: [String: VirtualNotchRule]) -> [NotchHousing] {
        VirtualNotch.housings(displays, rules: rules)
    }
}

/// The volume of the Mac's default output, and a call when it changes.
@MainActor
public protocol VolumeControl: AnyObject {
    /// From 0 to 1, or `nil` when the output has no volume Warble can change.
    var volume: Double? { get }
    var isMuted: Bool { get }
    func set(_ volume: Double)
    func startListening(_ onChange: @escaping () -> Void)
    func stopListening()
}

/// The Mac's sound outputs, which one plays, and a call when either changes.
@MainActor
public protocol AudioOutputs: AnyObject {
    var all: [AudioOutput] { get }
    var current: UInt32 { get }
    func select(_ id: UInt32)
    func startListening(_ onChange: @escaping () -> Void)
    func stopListening()
}

/// Where the last track played is kept across launches, and how its art is shrunk for the idle card.
public protocol LastPlayedStore: Sendable {
    func load() -> LastPlayed?
    func save(_ lastPlayed: LastPlayed) throws
    func remembering(_ state: PlaybackState, appName: String?) -> LastPlayed
}
