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

/// Takes a key from every app for a while, such as Escape while a notch is open. Each owner holds one key of its own, so
/// owners never take each other's.
@MainActor
public protocol HotkeyRegistrar: AnyObject {
    /// Replaces any key `owner` held before; false when macOS refused it.
    @discardableResult
    func registerTemporary(_ combo: KeyCombo, for owner: TemporaryKey, onPress: @escaping () -> Void) -> Bool
    /// Lets go of the key `owner` holds, and of no other.
    func unregisterTemporary(for owner: TemporaryKey)
}

/// Who holds a temporary key.
public enum TemporaryKey: CaseIterable, Sendable {
    /// Escape while a notch is open.
    case notch
    /// ⌘Z while a toast offers Undo.
    case toast
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

/// Listens to the Mac's audio for the live waveform. Starting it is what makes macOS ask to record, so it runs only while the
/// bars are on screen.
@MainActor
public protocol AudioTap: AnyObject {
    /// Starts listening. `onFrame` gets one magnitude for each of `SpectrumBars`' bands, about 15 times a second, off the
    /// main actor. `onFailure` is called once, off the main actor, if macOS refuses or the tap can't start.
    func start(onFrame: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable () -> Void)
    /// Stops listening and lets go of everything it held.
    func stop()
}

/// Where the last track played is kept across launches.
public protocol LastPlayedStore: Sendable {
    func load() -> LastPlayed?
    func save(_ lastPlayed: LastPlayed) throws
}

/// Keeps the last track played only while Warble runs, so the preview neither reads nor saves the real one, and a test
/// can see what was saved. Open so a test can slow a save down.
open class LastPlayedInMemory: LastPlayedStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _saved: [LastPlayed] = []
    private var _stored: LastPlayed?

    /// What `load` returns. Saving doesn't change it, since the preview starts from what it's given.
    public var stored: LastPlayed? {
        get { lock.withLock { _stored } }
        set { lock.withLock { _stored = newValue } }
    }

    /// Every track saved, in the order the saves landed.
    public var saved: [LastPlayed] {
        lock.withLock { _saved }
    }

    public init() {}

    public func load() -> LastPlayed? {
        stored
    }

    open func save(_ lastPlayed: LastPlayed) throws {
        lock.withLock { _saved.append(lastPlayed) }
    }
}

/// Where a track's synced lyrics come from. Only asked while Settings turns lyrics on.
public protocol LyricsProvider: Sendable {
    /// The track's synced lyrics as LRC text, or `nil` when there are none or they can't be had.
    func lyrics(for query: LyricsQuery) async -> String?
}
