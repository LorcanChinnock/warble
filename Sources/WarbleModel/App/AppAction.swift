import Foundation

/// Something that happened, which `reduce` turns into a new `AppState` and any `AppEffect`s.
public enum AppAction: Equatable, Sendable {
    /// What a source reports playing, or `nil` when it reports nothing. A guess at what a command will do comes in the
    /// same way, so it shows at once and the app's next report replaces it.
    case playbackReported(PlaybackState?)
    /// The housings the displays and their rules call for now.
    case housingsChanged([NotchHousing])
    /// The pointer entered or left the area of `display`'s notch that keeps it open.
    case pointer(display: String, inside: Bool)
    /// Something the user did to `display`'s notch. A click or the keyboard shortcut also closes any other notch.
    case hover(display: String, HoverEvent)
    /// A menu from `display`'s notch opened (true) or closed, which keeps an open card open under it.
    case menu(display: String, open: Bool)
    /// The open card on `display` swapped to the Doctor's checks (true) or back to the player.
    case showDoctor(display: String, Bool)
    /// A click outside, Escape, or Esc in a notch with the keyboard: every open notch closes, but `except`.
    case dismiss(except: String?)
    /// Whether a Doctor check failed.
    case attentionChanged(Bool)
    /// Settings changed.
    case stayVisibleChanged(TimeInterval)
    case idleHoverChanged(IdleHover)
    case trackToastChanged(Bool)
    /// `AppState.deadline` came due.
    case tick
}
