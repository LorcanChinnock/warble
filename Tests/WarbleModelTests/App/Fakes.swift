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

/// Holds a temporary key for each owner, as `HotkeyCenter` does, and presses one when a test says so.
@MainActor
final class FakeHotkeys: HotkeyRegistrar {
    private(set) var temporary: [TemporaryKey: KeyCombo] = [:]
    var refuses = false
    private(set) var unregisters = 0
    private var onPress: [TemporaryKey: () -> Void] = [:]

    func registerTemporary(_ combo: KeyCombo, for owner: TemporaryKey, onPress: @escaping () -> Void) -> Bool {
        guard !refuses else { return false }
        temporary[owner] = combo
        self.onPress[owner] = onPress
        return true
    }

    func unregisterTemporary(for owner: TemporaryKey) {
        unregisters += 1
        temporary[owner] = nil
        onPress[owner] = nil
    }

    func press(_ owner: TemporaryKey) {
        onPress[owner]?()
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

/// A volume a test sets, which calls back as Core Audio would when it changes.
@MainActor
final class FakeVolume: VolumeControl {
    var volume: Double? = 0.5
    var isMuted = false
    private(set) var listening = false
    private var onChange: (() -> Void)?

    func set(_ volume: Double) {
        self.volume = volume
    }

    func startListening(_ onChange: @escaping () -> Void) {
        listening = true
        self.onChange = onChange
    }

    func stopListening() {
        listening = false
        onChange = nil
    }

    /// The volume keys changed it.
    func change(to volume: Double) {
        self.volume = volume
        onChange?()
    }
}

@MainActor
final class FakeOutputs: AudioOutputs {
    var all = [AudioOutput(id: 1, name: "MacBook Air Speakers", transport: .builtIn), AudioOutput(id: 2, name: "AirPods", transport: .bluetooth)]
    var current: UInt32 = 1
    private(set) var listening = false

    func select(_ id: UInt32) {
        current = id
    }

    func startListening(_ onChange: @escaping () -> Void) {
        listening = true
    }

    func stopListening() {
        listening = false
    }
}

/// Keeps what's saved in memory, and can hold a save back until a test lets it go, to check the order saves land in.
final class FakeLastPlayed: LastPlayedStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _saved: [LastPlayed] = []
    var stored: LastPlayed?

    var saved: [LastPlayed] {
        lock.withLock { _saved }
    }

    func load() -> LastPlayed? {
        stored
    }

    func save(_ lastPlayed: LastPlayed) throws {
        // The first save is slow, so a later one would overtake it without the chain.
        if lock.withLock({ _saved.isEmpty }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        lock.withLock { _saved.append(lastPlayed) }
    }

    func remembering(_ state: PlaybackState, appName: String?) -> LastPlayed {
        LastPlayed(bundleIdentifier: state.bundleIdentifier, appName: appName, title: state.title, artist: state.artist, artwork: state.artwork)
    }
}

@MainActor
func makeRunner(hotkeys: FakeHotkeys = FakeHotkeys(), volume: FakeVolume = FakeVolume(), outputs: FakeOutputs = FakeOutputs(), lastPlayed: FakeLastPlayed = FakeLastPlayed()) -> EffectRunner {
    EffectRunner(hotkeys: hotkeys, volume: volume, outputs: outputs, lastPlayed: lastPlayed)
}

/// A player that records the commands it's sent.
actor FakeSource: NowPlayingSource {
    nonisolated let states = AsyncStream<PlaybackState?> { _ in }
    private(set) var sent: [PlaybackCommand] = []

    func send(_ command: PlaybackCommand) async {
        sent.append(command)
    }
}
