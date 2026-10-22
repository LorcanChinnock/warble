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
    /// Open the notch the pointer is on with the keyboard in it, or close it again.
    case toggleKeyboard
    case openApp(bundleIdentifier: String)
    case setVolume(Double)
    /// A light tick on a Force Touch trackpad.
    case haptic
    case selectOutput(UInt32)
    /// Shrink the art of `PlaybackState` for the idle card, then answer `.remembered` with `pass`.
    case remember(PlaybackState, pass: Int)
    /// Save the last track played for the next launch; the latest save wins.
    case saveLastPlayed(LastPlayed)
    /// Gather the Doctor's facts, then answer `.factsGathered` with `pass`.
    case gatherFacts(Doctor.Adapter, pass: Int)
    /// Look up the track's synced lyrics and parse them, then answer `.lyricsLoaded` with `pass`.
    case fetchLyrics(LyricsQuery, pass: Int)
    /// Open the welcome window, which `.welcomeClosed` answers.
    case showWelcome
    /// Watch Music and Spotify open and quit (true), or stop.
    case followPlayers(Bool)
    /// Open the socket the `warble` command talks to (true), or close it and remove it. Asked once when the setting changes.
    case listenForCommands(Bool)
    /// Open Settings, on the section with this name if it's one of `RemoteCommand.settingsSections`.
    case openSettings(section: String?)
}
