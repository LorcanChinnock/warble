import Foundation

/// Something that happened, which `reduce` turns into a new `AppState` and any `AppEffect`s.
public enum AppAction: Equatable, Sendable {
    /// What a source reports playing, or `nil` when it reports nothing. A guess at what a command will do comes in the
    /// same way, so it shows at once and the app's next report replaces it.
    case playbackReported(PlaybackState?)
    /// The housings the displays and their rules call for now.
    case housingsChanged([NotchHousing])
    /// The displays that show a full-screen app now, by `NotchDisplay.id`.
    case fullScreenChanged(Set<String>)
    /// The pointer entered or left the area of `display`'s notch that keeps it open.
    case pointer(display: String, inside: Bool)
    /// Something the user did to `display`'s notch. A click also closes any other notch.
    case hover(display: String, HoverEvent)
    /// A menu from `display`'s notch opened (true) or closed, which keeps an open card open under it.
    case menu(display: String, open: Bool)
    /// A click outside or Escape: every open notch closes, but `except`.
    case dismiss(except: String?)
    /// A command from a notch button or a key in an open notch, which shows what it will do at once.
    case command(PlaybackCommand)
    /// Bring the app that's playing to the front, or while Idle the one that played last.
    case openApp
    /// Play the last track again from the idle card: resume the session if the app still has one, otherwise open the
    /// track, or the app that played it.
    case resumeLastPlayed
    /// Volume from the slider or a scroll over a notch. A scroll carries the volume read just before, since the card that follows it may not be open.
    case setVolume(Double)
    /// A scroll over a notch: `delta` up and down, as `NSEvent.scrollingDeltaY` reports it.
    case scrolled(delta: Double, precise: Bool, inverted: Bool, volume: Double?, isMuted: Bool)
    case volumeRead(Double?, isMuted: Bool)
    case selectOutput(UInt32)
    case outputsRead([AudioOutput], current: UInt32?)
    /// The last track played, read from disk at launch or shrunk for the idle card after `.remember`.
    case lastPlayedLoaded(LastPlayed?)
    case remembered(LastPlayed, pass: Int)
    /// Settings changed.
    case stayVisibleChanged(TimeInterval)
    case virtualTitleChanged(Bool)
    /// `AppState.deadline` came due.
    case tick
}
