import Foundation

/// Something that happened, which `reduce` turns into a new `AppState` and any `AppEffect`s.
public enum AppAction: Equatable, Sendable {
    /// What a source reports playing, or `nil` when it reports nothing. A guess at what a command will do comes in the
    /// same way, so it shows at once and the app's next report replaces it.
    case playbackReported(PlaybackState?)
    /// The housings the displays call for now.
    case housingsChanged([NotchHousing])
    /// The displays that show a full-screen app now, by `NotchDisplay.id`.
    case fullScreenChanged(Set<String>)
    /// The pointer entered or left the area of `display`'s notch that keeps it open.
    case pointer(display: String, inside: Bool)
    /// Something the user did to `display`'s notch.
    case hover(display: String, HoverEvent)
    /// A menu from `display`'s notch opened (true) or closed, which keeps an open card open under it.
    case menu(display: String, open: Bool)
    /// A click outside or Escape: every open notch closes, but `except`.
    case dismiss(except: String?)
    /// A command from a notch button or a key in an open notch, which shows what it will do at once.
    case command(PlaybackCommand)
    /// Play the remembered track again, from the Idle notch's card.
    case resumeLast
    /// Bring the app that's playing to the front.
    case openApp
    /// A click on the notch itself: bring the playing app to the front, unless the notch is empty or showing its note.
    case notchClicked
    /// Open the page of the artist that's playing, or the app when Warble can't find it.
    case openArtist
    /// Volume from the slider or a scroll over a notch. A scroll carries the volume read just before, since the card that follows it may not be open.
    case setVolume(Double)
    /// A scroll over a notch: `delta` up and down, as `NSEvent.scrollingDeltaY` reports it.
    case scrolled(delta: Double, precise: Bool, inverted: Bool, volume: Double?, isMuted: Bool)
    /// A slide sideways over a notch: seconds to move through the song, forward when positive.
    case scrubbed(by: TimeInterval)
    /// A quick flick sideways over a notch, to the next track or back to the previous one.
    case flicked(next: Bool)
    case volumeRead(Double?, isMuted: Bool)
    case selectOutput(UInt32)
    case outputsRead([AudioOutput], current: UInt32?)
    /// Settings turned the title in a virtual notch on or off.
    case virtualTitleChanged(Bool)
    /// Settings chose when a virtual notch is there.
    case virtualVisibilityChanged(VirtualNotchVisibility)
    /// Settings chose how long a paused song stays in the notch.
    case pauseDelayChanged(PauseDelay)
    /// Settings chose how big the card the notch opens into is.
    case cardSizeChanged(CardSize)
    /// Settings chose the face of the notch's title.
    case fontChanged(NotchFont)
    /// `AppState.deadline` came due.
    case tick
}

extension AppAction {
    /// Whether this is a click or key on play/pause, which the app times from the input to the next frame.
    public var isPlayPause: Bool {
        switch self {
        case .command(.togglePlayPause), .command(.play), .command(.pause): true
        default: false
        }
    }
}
