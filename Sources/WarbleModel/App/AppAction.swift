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
    /// Something the user did to `display`'s notch. A click or the keyboard shortcut also closes any other notch.
    case hover(display: String, HoverEvent)
    /// A menu from `display`'s notch opened (true) or closed, which keeps an open card open under it.
    case menu(display: String, open: Bool)
    /// The open card on `display` swapped to the Doctor's checks (true) or back to the player.
    case showDoctor(display: String, Bool)
    /// The open card on `display` swapped to the lyrics (true) or back to the player.
    case showLyrics(display: String, Bool)
    /// A click outside, Escape, or Esc in a notch with the keyboard: every open notch closes, but `except`.
    case dismiss(except: String?)
    /// A command from a notch button or a key in an open notch, which shows what it will do at once.
    case command(PlaybackCommand)
    /// Back or forward through a podcast or audiobook by `by` seconds from where it is, from the player's card.
    case skip(by: TimeInterval)
    /// The player's card started a sleep timer, or turned the one running off with `nil`.
    case setSleepTimer(SleepTimer.Choice?)
    /// One of Warble's actions, from a global shortcut, and later the command line, links and Shortcuts.
    case perform(WarbleAction)
    /// Bring the app that's playing to the front, or while Idle the one that played last.
    case openApp
    /// Play the last track again from the idle card: resume the session if the app still has one, otherwise open the
    /// track, or the app that played it.
    case resumeLastPlayed
    /// Volume from the slider, a scroll over a notch, or the arrow keys in a notch with the keyboard. A scroll and a key
    /// carry the volume read just before, since the card that follows it may not be open.
    case setVolume(Double)
    /// A scroll over a notch: `delta` up and down, as `NSEvent.scrollingDeltaY` reports it, `across` as `scrollingDeltaX`
    /// does, and the `phase` of the trackpad gesture it's part of, or `nil` for a mouse wheel. A sideways swipe skips
    /// when Settings turns it on.
    case scrolled(
        delta: Double, across: Double = 0, phase: Swipe.Phase? = nil, precise: Bool, inverted: Bool, volume: Double?, isMuted: Bool
    )
    case volumeKey(delta: Double, volume: Double?, isMuted: Bool)
    case volumeRead(Double?, isMuted: Bool)
    case selectOutput(UInt32)
    case outputsRead([AudioOutput], current: UInt32?)
    /// The last track played, read from disk at launch or shrunk for the idle card after `.remember`.
    case lastPlayedLoaded(LastPlayed?)
    case remembered(LastPlayed, pass: Int)
    /// How the adapter is doing, as the app last saw it.
    case adapterChanged(Doctor.Adapter)
    /// What the Doctor found for the refresh numbered `pass`.
    case factsGathered(Doctor.Facts, pass: Int)
    /// Music or Spotify opened or quit, or macOS refused a script: check again.
    case playersChanged
    case automationDenied
    /// The AppleScript fallback reported, which clears a failing Automation check once the user allowed it.
    case fallbackReported
    /// Not now on the Doctor's card: hide the "!" for what fails now.
    case notNow
    /// Settings changed.
    case stayVisibleChanged(TimeInterval)
    case idleHoverChanged(IdleHover)
    case trackToastChanged(Bool)
    case toastsInFullScreenChanged(Bool)
    case lyricsChanged(Bool)
    case swipeToSkipChanged(Bool)
    case podcastSkipsChanged(Bool)
    case dragArtOutChanged(Bool)
    case sleepTimerSettingChanged(Bool)
    case hidesFromCaptureChanged(Bool)
    case virtualTitleChanged(Bool)
    case linksChanged(Bool)
    /// The Developer card turned the `warble` command line on or off.
    case commandLineChanged(Bool)
    /// A `warble://` link was opened. It does what the notch's matching button does while Settings has links on, and
    /// nothing while they're off.
    case linkOpened(RemoteCommand)
    /// The lyrics found for the fetch numbered `pass`, or `nil` when there are none.
    case lyricsLoaded(Lyrics?, pass: Int)
    /// Warble opened, with whether it's the first time. Dispatched once, by `AppDelegate`.
    case launched(firstRun: Bool)
    /// The welcome window closed.
    case welcomeClosed
    /// `AppState.deadline` came due.
    case tick
}
