import Foundation

/// Carries out the effects that go through a port, and hands the rest, which need AppKit, to `platform`. Slow work, such
/// as shrinking art or writing a file, runs off the main actor, and its answer comes back as an action.
@MainActor
public final class EffectRunner {
    private let hotkeys: any HotkeyRegistrar
    private let volume: any VolumeControl
    private let outputs: any AudioOutputs
    private let lastPlayed: any LastPlayedStore
    /// Makes what's kept of a report, with its art shrunk for the idle card. Slow, so it runs off the main actor.
    private let remember: @Sendable (PlaybackState, String?) -> LastPlayed
    /// Where lyrics come from, or `nil` when there's nowhere to ask, so every fetch finds none.
    private let lyrics: (any LyricsProvider)?
    private let stats: any StatsStore
    /// The tap behind the live waveform, or `nil` where there isn't one.
    private let audioTap: (any AudioTap)?
    /// Where each frame of the waveform's bands goes, off the main actor. Frames never pass through `reduce`, since 30 a
    /// second would put work on the hover path for something only the bars draw.
    public var spectrum: @Sendable ([Float]) -> Void = { _ in }
    /// Which start of the tap a failure belongs to, so one that comes after a stop is ignored.
    private var tapRun = 0
    /// Carries out the effects that need AppKit. The app sets it, since it owns what they change.
    public var platform: (AppEffect) -> Void = { _ in }
    /// Where an answer goes back in as an action. The store sets it once both exist.
    public var dispatch: (AppAction) -> Void = { _ in }
    /// The app that's playing reports through it and takes commands, or `nil` before one starts.
    public var source: (any NowPlayingSource)?
    /// The address of the page a browser shows for a track that just started there, or `nil` when the setting is off, the
    /// browser can't say or its front tab isn't the track. Asks the browser, so it runs off the main actor.
    public var tabLink: @Sendable (_ bundleIdentifier: String, _ title: String) async -> URL? = { _, _ in nil }
    /// The name of the app with a bundle identifier, for the idle card's VoiceOver label.
    public var appName: (String) -> String? = { _ in nil }
    /// Logs a failure, such as a save that didn't work.
    public var logError: @Sendable (String) -> Void = { _ in }
    /// Whether Escape is Warble's now, so it's taken once and let go of only when held.
    private var holdsEscape = false
    private var followsVolume = false
    /// The write in flight, which the next one waits for, so the file always ends up holding the latest track.
    private var saving: Task<Void, Never>?
    /// The lyrics fetch in flight, which the next waits for, and the pass of the latest asked for. A fetch whose turn
    /// comes after a newer one was asked for is dropped unsent, so skipping through ten tracks asks for the one in
    /// flight and the latest, never the eight between, and the latest is always asked.
    private var fetching: Task<Void, Never>?
    private var latestFetch: Int?
    /// The stats' latest write, read or clear, which the next waits for, so they land in the order they were asked for.
    private var keeping: Task<Void, Never>?
    /// The reads under way, each gone once it answers.
    private var reading: [UUID: Task<Void, Never>] = [:]

    public init(
        hotkeys: any HotkeyRegistrar, volume: any VolumeControl, outputs: any AudioOutputs, lastPlayed: any LastPlayedStore,
        remember: @escaping @Sendable (PlaybackState, String?) -> LastPlayed, lyrics: (any LyricsProvider)?,
        audioTap: (any AudioTap)? = nil, stats: any StatsStore = StatsInMemory()
    ) {
        self.hotkeys = hotkeys
        self.volume = volume
        self.outputs = outputs
        self.lastPlayed = lastPlayed
        self.remember = remember
        self.lyrics = lyrics
        self.audioTap = audioTap
        self.stats = stats
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
            let remember = remember
            let tabLink = tabLink
            let appName = appName(state.bundleIdentifier)
            read {
                await Task.detached(priority: .utility) {
                    var track = remember(state, appName)
                    if track.link == nil, Browser(rawValue: track.bundleIdentifier) != nil {
                        track.link = await tabLink(track.bundleIdentifier, track.title)
                    }
                    return track
                }.value
            } answer: {
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
        case .fetchLyrics(let query, let pass):
            latestFetch = pass
            let previous = fetching
            let provider = lyrics
            fetching = Task { [weak self] in
                await previous?.value
                guard let self, pass == self.latestFetch else { return }
                // Parsed off the main actor too, since a song's lyrics can run to hundreds of lines.
                let found = await Task.detached(priority: .utility) {
                    await provider?.lyrics(for: query).flatMap(Lyrics.init(lrc:))
                }.value
                self.dispatch(.lyricsLoaded(found, pass: pass))
            }
        case .captureAudio(let capture):
            captureAudio(capture)
        case .recordListening(let span):
            keep { stats, logError in
                do {
                    try stats.append(span)
                } catch {
                    logError("Couldn't save listening stats: \(error.localizedDescription)")
                }
            }
        case .loadStats(let since):
            keep { [weak self] stats, _ in
                let spans = stats.load(since: since)
                await self?.statsLoaded(spans)
            }
        case .clearStats:
            keep { stats, logError in
                do {
                    try stats.clear()
                } catch {
                    logError("Couldn't clear listening stats: \(error.localizedDescription)")
                }
            }
        case .watchClicksOutside, .turnOffWaveform, .openApp, .launchAndPlay, .openLink, .haptic, .gatherFacts, .followPlayers, .toggleKeyboard, .showWelcome:
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

    private func statsLoaded(_ spans: [ListenedSpan]) {
        dispatch(.statsLoaded(spans))
    }

    /// Runs `work` off the main actor once the stats work before it is done.
    private func keep(_ work: @escaping @Sendable (any StatsStore, @Sendable (String) -> Void) async -> Void) {
        let stats = stats
        let previous = keeping
        let logError = logError
        keeping = Task.detached(priority: .utility) {
            await previous?.value
            await work(stats, logError)
        }
    }

    /// Blocks until the stats work under way is done, for when Warble is quitting and nothing runs after. It gives up after
    /// `timeout` seconds.
    public func flushStats(timeout: TimeInterval = 1) {
        guard let keeping else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await keeping.value
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    /// Waits for the reads and writes under way, for a test.
    func finish() async {
        while let read = reading.values.first {
            await read.value
        }
        await saving?.value
        await fetching?.value
        await keeping?.value
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

    private func captureAudio(_ capture: Bool) {
        tapRun += 1
        guard let audioTap else { return }
        guard capture else {
            audioTap.stop()
            return
        }
        let run = tapRun
        let spectrum = spectrum
        audioTap.start(onFrame: { spectrum($0) }, onFailure: { [weak self] in
            Task { @MainActor in
                guard let self, self.tapRun == run else { return }
                self.dispatch(.audioCaptureDenied)
            }
        })
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
