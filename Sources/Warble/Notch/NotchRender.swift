import AppKit
import WarbleCore

/// What one surface shows, worked out from the store's state for its display. `NotchSurface.render` takes it whole, so
/// everything the panel draws comes from one value and is set in one place.
struct NotchRender: Equatable {
    var state: NotchState
    var isPlaying: Bool
    /// A notch over a full-screen app lets clicks through to the app, since it draws nothing there.
    var ignoresMouseEvents: Bool

    /// `nil` when the display has no surface or the store has no state for it, so the last render stands.
    init?(_ app: AppState, display: String) {
        guard let surface = app.surfaces[display], let state = app.notchState(display) else { return nil }
        self.state = state
        isPlaying = app.showsPlayback
        ignoresMouseEvents = surface.isFullScreen
    }
}
