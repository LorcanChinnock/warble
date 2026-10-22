import Foundation

/// Carries out the effects that go through a port, and hands the rest, which need AppKit, to `platform`. Slow work, such
/// as shrinking art or writing a file, runs off the main actor, and its answer comes back as an action.
@MainActor
public final class EffectRunner {
    private let hotkeys: any HotkeyRegistrar
    private let volume: any VolumeControl
    private let outputs: any AudioOutputs
    private let lastPlayed: any LastPlayedStore
    /// Carries out the effects that need AppKit. The app sets it, since it owns what they change.
    public var platform: (AppEffect) -> Void = { _ in }
    /// Where an answer goes back in as an action. The store sets it once both exist.
    public var dispatch: (AppAction) -> Void = { _ in }
    /// The app that's playing reports through it and takes commands, or `nil` before one starts.
    public var source: (any NowPlayingSource)?
    /// The name of the app with a bundle identifier, for the idle card's VoiceOver label.
    public var appName: (String) -> String? = { _ in nil }
    /// Logs a failure, such as a save that didn't work.
    public var logError: @Sendable (String) -> Void = { _ in }
    /// Whether Escape is Warble's now, so it's taken once and let go of only when held.
    private var holdsEscape = false
    private var followsVolume = false
    /// The write in flight, which the next one waits for, so the file always ends up holding the latest track.
    private var saving: Task<Void, Never>?
    /// The reads under way, each gone once it answers.
    private var reading: [UUID: Task<Void, Never>] = [:]

    public init(hotkeys: any HotkeyRegistrar, volume: any VolumeControl, outputs: any AudioOutputs, lastPlayed: any LastPlayedStore) {
        self.hotkeys = hotkeys
        self.volume = volume
        self.outputs = outputs
        self.lastPlayed = lastPlayed
    }

    public func perform(_ effect: AppEffect) {
        switch effect {
        case .takeEscape(true):
            guard !holdsEscape else { return }
            holdsEscape = hotkeys.registerTemporary(.escape, for: .notch) { [weak self] in
                self?.dispatch(.dismiss(except: nil))
            }
        case .takeEscape(false):
            guard holdsEscape else { return }
            hotkeys.unregisterTemporary(for: .notch)
            holdsEscape = false
        case .followVolume(let follow):
            followVolume(follow)
        case .setVolume(let value):
            volume.set(value)
            readVolume()
        case .selectOutput(let id):
            // The volume's listener follows the new output, and reads its volume.
            outputs.select(id)
            readOutputs()
        case .send(let command):
            guard let source else { return }
            Task { await source.send(command) }
        case .remember(let state, let pass):
            let store = lastPlayed
            let appName = appName(state.bundleIdentifier)
            read { await Task.detached(priority: .utility) { store.remembering(state, appName: appName) }.value } answer: {
                .remembered($0, pass: pass)
            }
        case .saveLastPlayed(let track):
            let store = lastPlayed
            let previous = saving
            let logError = logError
            saving = Task.detached(priority: .utility) {
                await previous?.value
                do {
                    try store.save(track)
                } catch {
                    logError("Couldn't save the last track played: \(error.localizedDescription)")
                }
            }
        case .watchClicksOutside, .openApp, .haptic, .gatherFacts, .followPlayers, .toggleKeyboard:
            platform(effect)
        }
    }

    /// Reads the track saved last time, unless one has played since Warble opened.
    public func loadLastPlayed() {
        let store = lastPlayed
        read { await Task.detached(priority: .utility) { store.load() }.value } answer: { .lastPlayedLoaded($0) }
    }

    /// Runs `work` off the main actor and dispatches what `answer` makes of its result.
    private func read<Value: Sendable>(_ work: @escaping @Sendable () async -> Value, answer: @escaping (Value) -> AppAction) {
        let id = UUID()
        reading[id] = Task { [weak self] in
            let value = await work()
            self?.reading[id] = nil
            self?.dispatch(answer(value))
        }
    }

    /// Waits for the reads and writes under way, for a test.
    func finish() async {
        while let read = reading.values.first {
            await read.value
        }
        await saving?.value
    }

    /// Reads the volume and the outputs, and follows changes from the volume keys and elsewhere, only while the slider
    /// shows.
    private func followVolume(_ follow: Bool) {
        guard follow != followsVolume else { return }
        followsVolume = follow
        if follow {
            readVolume()
            readOutputs()
            volume.startListening { [weak self] in self?.readVolume() }
            outputs.startListening { [weak self] in self?.readOutputs() }
        } else {
            volume.stopListening()
            outputs.stopListening()
        }
    }

    private func readVolume() {
        dispatch(.volumeRead(volume.volume, isMuted: volume.isMuted))
    }

    private func readOutputs() {
        dispatch(.outputsRead(outputs.all, current: outputs.current))
    }
}

extension KeyCombo {
    /// Escape with no modifiers.
    public static let escape = KeyCombo(keyCode: 53, modifiers: 0)
}
