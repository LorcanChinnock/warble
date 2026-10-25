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

/// Holds the first save back, so a later one would overtake it without the chain.
final class FakeLastPlayed: LastPlayedInMemory, @unchecked Sendable {
    override func save(_ lastPlayed: LastPlayed) throws {
        if saved.isEmpty {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try super.save(lastPlayed)
    }
}

/// Holds the first write back, so a later one would overtake it without the chain.
final class FakeStats: StatsInMemory, @unchecked Sendable {
    override func append(_ span: ListenedSpan) throws {
        if saved.isEmpty {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try super.append(span)
    }
}

/// What the app remembers of a report, without shrinking its art.
func remembering(_ state: PlaybackState, appName: String?) -> LastPlayed {
    LastPlayed(bundleIdentifier: state.bundleIdentifier, appName: appName, title: state.title, artist: state.artist, artwork: state.artwork, link: state.link)
}

/// Answers each track with the LRC a test gives it, and records what it was asked.
final class FakeLyrics: LyricsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [LyricsQuery] = []
    /// LRC text by track title.
    var lrc: [String: String] = [:]

    var asked: [LyricsQuery] {
        lock.withLock { _asked }
    }

    init(_ lrc: [String: String] = [:]) {
        self.lrc = lrc
    }

    func lyrics(for query: LyricsQuery) async -> String? {
        lock.withLock {
            _asked.append(query)
            return lrc[query.title]
        }
    }
}

@MainActor
func makeRunner(
    hotkeys: FakeHotkeys = FakeHotkeys(), volume: FakeVolume = FakeVolume(), outputs: FakeOutputs = FakeOutputs(),
    lastPlayed: FakeLastPlayed = FakeLastPlayed(), lyrics: FakeLyrics = FakeLyrics(), audioTap: FakeAudioTap? = nil,
    stats: FakeStats = FakeStats()
) -> EffectRunner {
    EffectRunner(
        hotkeys: hotkeys, volume: volume, outputs: outputs, lastPlayed: lastPlayed, remember: { remembering($0, appName: $1) },
        lyrics: lyrics, audioTap: audioTap, stats: stats
    )
}

/// An audio tap that records starts and stops, and sends frames or fails when a test says so.
@MainActor
final class FakeAudioTap: AudioTap {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var isRunning = false
    private var onFrame: (@Sendable ([Float]) -> Void)?
    private var onFailure: (@Sendable () -> Void)?
    /// Every start's failure callback, including those of starts that were stopped since.
    private var failures: [@Sendable () -> Void] = []

    func start(onFrame: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable () -> Void) {
        starts += 1
        isRunning = true
        self.onFrame = onFrame
        self.onFailure = onFailure
        failures.append(onFailure)
    }

    func stop() {
        stops += 1
        isRunning = false
        onFrame = nil
        onFailure = nil
    }

    func emit(_ bands: [Float]) {
        onFrame?(bands)
    }

    func fail() {
        onFailure?()
    }

    /// Fails the first start, which may have been stopped since.
    func failEarlier() {
        failures.first?()
    }
}

/// A player that records the commands it's sent.
actor FakeSource: NowPlayingSource {
    nonisolated let states = AsyncStream<PlaybackState?> { _ in }
    private(set) var sent: [PlaybackCommand] = []

    func send(_ command: PlaybackCommand) async {
        sent.append(command)
    }
}
