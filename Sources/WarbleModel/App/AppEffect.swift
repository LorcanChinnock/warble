import Foundation

/// Work `reduce` asks for outside the state, as data, so a test can check it was asked for and the app target carries it
/// out. Each is asked for once when what it depends on changes.
public enum AppEffect: Equatable, Sendable {
    /// Close the open notches on a click in another app (true), or stop watching (false). Only while a notch is open.
    case watchClicksOutside(Bool)
    /// Take Escape from every app (true), to close the notch the pointer is on, or let it go.
    case takeEscape(Bool)
    /// Read the volume and outputs and follow their changes (true), only while the player's card is open.
    case followVolume(Bool)
    /// Send a command to the app that's playing.
    case send(PlaybackCommand)
    /// Bring the playing app to the front, and in a browser the tab, which is the one titled `title`.
    case openApp(bundleIdentifier: String, title: String)
    /// Open the artist's page for the track titled `title`, or `openApp` when there's no exact one to open.
    case openArtist(bundleIdentifier: String, title: String)
    case setVolume(Double)
    /// A light tick on a Force Touch trackpad.
    case haptic
    case selectOutput(UInt32)
}
