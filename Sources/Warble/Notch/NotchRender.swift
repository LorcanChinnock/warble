import AppKit
import WarbleCore

/// What one surface shows, worked out from the store's state for its display. `NotchSurface.render` takes it whole, so
/// everything the panel draws comes from one value and is set in one place.
struct NotchRender: Equatable {
    var state: NotchState
    var card: NotchCard
    var isPlaying: Bool
    var toast: TrackToast?
    var skipsBySeconds: Bool
    var artDrag: ArtDrag?
    var isVirtual: Bool
    var showsTitle: Bool
    var isAlwaysShown: Bool
    var showsDoctor: Bool
    /// A toast over a full-screen app lets clicks through to the app, since it takes no hover or click.
    var ignoresMouseEvents: Bool

    /// `nil` when the display has no surface or the store has no state for it, so the last render stands.
    init?(_ app: AppState, display: String) {
        guard let surface = app.surfaces[display], let state = app.notchState(display), let card = app.card(display) else { return nil }
        self.state = state
        self.card = card
        isPlaying = app.drawsPlayback
        toast = app.toasts.current?.content
        skipsBySeconds = app.skipsBySeconds
        artDrag = app.artDrag
        isVirtual = surface.isVirtual
        showsTitle = app.titleInNotch(display)
        isAlwaysShown = surface.isAlwaysShown
        showsDoctor = surface.showsDoctor
        ignoresMouseEvents = surface.isFullScreen
    }

    /// The toast only while its state is the one showing it.
    var shownToast: TrackToast? { state == .toast ? toast : nil }
}
