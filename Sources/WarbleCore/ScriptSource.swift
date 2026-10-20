import AppKit
import Foundation
import os
import WarbleModel

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "now-playing")

/// Reads what Music and Spotify are playing, and controls them, with AppleScript. It stands in for `AdapterSource` only
/// when the adapter can't run, so Warble still works with the two most common players after a macOS update breaks it.
///
/// It reads a player when the player posts its change notification, and never polls, so it costs nothing while nothing
/// changes. It only scripts a player that's running, so macOS asks for Automation permission once per player, the first
/// time that player plays.
@MainActor
public final class ScriptSource: NowPlayingSource {
    public nonisolated let states: AsyncStream<PlaybackState?>
    private let continuation: AsyncStream<PlaybackState?>.Continuation
    private var players = ScriptedNowPlaying()
    private var shown: PlaybackState?
    /// Each player's artwork, which is read only when its track changes.
    private var artwork: [ScriptedPlayer: (track: PlaybackState, data: Data?)] = [:]
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    /// Bumped by each read of a player, so a read that a later one overtook, while it fetched artwork, is dropped.
    private var reads: [ScriptedPlayer: Int] = [:]

    /// Scripts run one at a time, off the main thread: a player that's busy, or a permission prompt, holds a script up.
    private nonisolated static let queue = DispatchQueue(label: "Warble.ScriptSource")

    public init() {
        (states, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func start() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for player in ScriptedPlayer.allCases {
            let token = distributed.addObserver(forName: Notification.Name(player.changeNotification), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.read(player) }
            }
            observers.append((distributed, token))
        }
        // A player that quits posts nothing.
        let workspace = NSWorkspace.shared.notificationCenter
        let token = workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = app?.bundleIdentifier.flatMap(ScriptedPlayer.init(rawValue:)) else { return }
            MainActor.assumeIsolated { self?.forget(player) }
        }
        observers.append((workspace, token))
        log.notice("Following Music and Spotify with AppleScript")
        for player in ScriptedPlayer.allCases where Self.isRunning(player) {
            read(player)
        }
    }

    public func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
    }

    public func send(_ command: PlaybackCommand) async {
        guard let player = shown.flatMap({ ScriptedPlayer(rawValue: $0.bundleIdentifier) }), Self.isRunning(player) else { return }
        _ = await Self.run(player.script(for: command))
        // A seek, shuffle or repeat posts no notification.
        read(player)
    }

    private func read(_ player: ScriptedPlayer) {
        guard Self.isRunning(player) else {
            forget(player)
            return
        }
        reads[player, default: 0] += 1
        let read = reads[player]
        Task {
            let report = await Self.run(player.stateScript)
            var state = report.flatMap { PlaybackState(player: player, report: $0, at: .now) }
            if let track = state {
                state?.artwork = await artwork(for: track, of: player, url: report.flatMap(PlaybackState.artworkURL(in:)))
            }
            guard reads[player] == read else { return }
            update(player, state)
        }
    }

    /// Shows `player` as stopped, including over a read that's still running.
    private func forget(_ player: ScriptedPlayer) {
        reads[player, default: 0] += 1
        update(player, nil)
    }

    /// The artwork for `track`, read again only when the track has changed.
    private func artwork(for track: PlaybackState, of player: ScriptedPlayer, url: URL?) async -> Data? {
        if let known = artwork[player], known.track.isSameTrack(as: track) {
            return known.data
        }
        var data: Data?
        if let script = player.artworkScript {
            data = await Self.runForData(script)
        } else if let url {
            do {
                data = try await URLSession.shared.data(from: url).0
            } catch {
                log.error("Artwork didn't download: \(error.localizedDescription, privacy: .public)")
            }
        }
        artwork[player] = (track, data)
        return data
    }

    private func update(_ player: ScriptedPlayer, _ state: PlaybackState?) {
        players.update(player, state)
        if state == nil {
            artwork[player] = nil
        }
        guard players.current != shown else { return }
        shown = players.current
        continuation.yield(shown)
    }

    private static func isRunning(_ player: ScriptedPlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    /// The items of the list `source` returns, or `nil` when it fails.
    private nonisolated static func run(_ source: String) async -> [ScriptValue]? {
        await execute(source) { result in
            (0..<result.numberOfItems).map { ScriptValue(result.atIndex($0 + 1)) }
        }
    }

    /// The bytes `source` returns, or `nil` when it fails or returns `missing value`.
    private nonisolated static func runForData(_ source: String) async -> Data? {
        await execute(source) { $0.artworkData } ?? nil
    }

    private nonisolated static func execute<T: Sendable>(_ source: String, _ read: @escaping @Sendable (NSAppleEventDescriptor) -> T) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
                    let number = error?[NSAppleScript.errorNumber] as? Int ?? 0
                    // -1743: the user turned off Automation for Warble. -1728: no track, or no artwork for it.
                    log.error("Script failed with error \(number): \(error?[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: read(result))
            }
        }
    }
}

extension ScriptValue {
    /// One item of a script's result; anything other than text, a number or a Boolean is `.missing`.
    public init(_ descriptor: NSAppleEventDescriptor?) {
        guard let descriptor else {
            self = .missing
            return
        }
        switch descriptor.descriptorType {
        case typeUnicodeText, typeUTF8Text, typeChar:
            self = descriptor.stringValue.map(ScriptValue.text) ?? .missing
        case typeSInt16, typeSInt32, typeSInt64, typeUInt32, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
            self = .number(descriptor.doubleValue)
        case typeTrue, typeFalse, typeBoolean:
            self = .bool(descriptor.booleanValue)
        default:
            self = .missing
        }
    }
}

extension NSAppleEventDescriptor {
    /// The encoded image an artwork script returned, or `nil` for `missing value`, the type 'msng'.
    public var artworkData: Data? {
        descriptorType == typeType ? nil : data
    }
}
