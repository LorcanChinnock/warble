import AppKit
import WarbleCore

/// What one surface shows, worked out from the store's state for its display. `NotchSurface.render` takes it whole, so
/// everything the panel draws comes from one value and is set in one place.
struct NotchRender: Equatable {
    var state: NotchState
    var card: NotchCard
    var isPlaying: Bool
    var toast: TrackToast?
    var lyric: String?
    var lyrics: LyricsExcerpt?
    /// The activities, ranked, which the wings and the cards' rows draw.
    var activities: [Activity]
    var hasLyrics: Bool
    var skipsBySeconds: Bool
    var artDrag: ArtDrag?
    var showsSleepTimer: Bool
    var sleepTimer: SleepTimer?
    var canSetSleepTimer: Bool
    var isVirtual: Bool
    var showsTitle: Bool
    var isAlwaysShown: Bool
    var showsDoctor: Bool
    /// Whether the audio tap runs, so the bars draw the sound rather than loop.
    var showsWaveform: Bool
    /// A toast over a full-screen app lets clicks through to the app, since it takes no hover or click.
    var ignoresMouseEvents: Bool
    /// The window server leaves the panel out of every capture, ScreenCaptureKit's included, and still draws it.
    var sharingType: NSWindow.SharingType

    /// `nil` when the display has no surface or the store has no state for it, so the last render stands.
    init?(_ app: AppState, display: String) {
        guard let surface = app.surfaces[display], let state = app.notchState(display), let card = app.card(display) else { return nil }
        self.state = state
        self.card = card
        isPlaying = app.drawsPlayback
        toast = app.toasts.current?.content
        lyric = app.lyrics.line?.text
        lyrics = app.lyrics.excerpt
        activities = app.activities.ranked
        hasLyrics = app.hasLyricsCard
        skipsBySeconds = app.skipsBySeconds
        artDrag = app.artDrag
        showsSleepTimer = app.showsSleepTimer
        sleepTimer = app.sleepTimer
        canSetSleepTimer = app.canSetSleepTimer
        isVirtual = surface.isVirtual
        showsTitle = app.titleInNotch(display)
        isAlwaysShown = surface.isAlwaysShown
        showsDoctor = surface.showsDoctor
        showsWaveform = app.capturesAudio
        ignoresMouseEvents = surface.isFullScreen
        sharingType = app.hidesFromCapture ? .none : .readOnly
    }

    /// The toast, lyric line and excerpt only while their state or card is the one showing them.
    var shownToast: TrackToast? { state == .toast ? toast : nil }
    var shownLyric: String? { state == .lyrics ? lyric : nil }
    var shownLyrics: LyricsExcerpt? { state == .expanded && card == .lyrics ? lyrics : nil }
}
