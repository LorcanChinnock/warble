import Foundation

/// An app the idle card's play button just opened, which has no session yet. Once it reports a paused track, Warble sends
/// play, so one click resumes it. It gives up after `timeout`, leaving the app open.
public struct AwaitedSession: Equatable, Sendable {
    /// How long an app gets to register a session: a slow launch, with room to restore its window.
    public static let timeout: TimeInterval = 10

    public let bundleIdentifier: String
    public let deadline: Date

    init(bundleIdentifier: String, at now: Date) {
        self.bundleIdentifier = bundleIdentifier
        deadline = now + Self.timeout
    }

    /// Whether Warble opens `bundleIdentifier` and waits for it to play. Not Spotify, which has its own script, nor Music,
    /// whose `play` after a cold launch can start an unrelated track, nor a browser, whose tab it can't know.
    static func waitsFor(_ bundleIdentifier: String) -> Bool {
        ScriptedPlayer(rawValue: bundleIdentifier) == nil && Browser(rawValue: bundleIdentifier) == nil
    }
}
