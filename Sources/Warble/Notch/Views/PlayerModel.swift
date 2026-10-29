import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// What's playing and the controls for it, which every display's notch shows. The artwork is decoded and its colours
/// picked once, however many notches there are.
@MainActor
@Observable
final class PlayerModel {
    var playback: PlaybackState? {
        didSet {
            let artworkChanged = playback?.artwork != oldValue?.artwork
            let appChanged = playback?.bundleIdentifier != oldValue?.bundleIdentifier
            if artworkChanged {
                artwork = playback?.artwork.flatMap(NSImage.init(data:))
            }
            if appChanged {
                appName = playback.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).first?.localizedName }
            }
            if artworkChanged || (appChanged && playback?.artwork == nil) {
                pickColours()
            }
        }
    }
    private(set) var artwork: NSImage?
    /// The last track that played, which the Idle notch offers again.
    var lastPlayed: PlaybackState? {
        didSet {
            guard lastPlayed?.artwork != oldValue?.artwork else { return }
            lastArtwork = lastPlayed?.artwork.flatMap(NSImage.init(data:))
        }
    }
    private(set) var lastArtwork: NSImage?
    /// The glow's colours, from the artwork or, without it, the app's icon.
    private(set) var colours: ArtworkColours?
    /// Whether the open card glows, which Settings can turn off. Off, no colours are picked unless Increase Contrast needs
    /// them for its border or `matchesAlbumColour` is on.
    var showsGlow = true {
        didSet {
            if showsGlow != oldValue { pickColours() }
        }
    }
    /// The face of the title, which Settings chooses.
    var notchFont = NotchFont.system
    /// Whether the title and the bars take the artwork's colour, which Settings can turn on. The colours are picked for it
    /// even with the glow off.
    var matchesAlbumColour = false {
        didSet {
            if matchesAlbumColour != oldValue { pickColours() }
        }
    }
    /// The artwork's colour for the title and the bars, or `nil` for white: while Settings has them follow it, and the
    /// artwork gave one. It is lightened where the cover is too dark to read on the black notch.
    var tint: NSColor? {
        guard matchesAlbumColour, let colours else { return nil }
        let rgb = colours.text(increasedContrast: increasesContrast)
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
    /// Whether Increase Contrast is on, kept here so a change redraws what depends on it.
    private var increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    /// Bumped by every pick, so a pick that finishes after the track has changed again is dropped.
    @ObservationIgnored private var colourPicks = 0
    /// The name of the app that's playing, for VoiceOver.
    private(set) var appName: String?
    /// The output's volume from 0 to 1, read while Expanded shows; `nil` when it can't be changed.
    var volume: Double?
    var isMuted = false
    /// The outputs to offer and the one playing, read while Expanded shows.
    var outputs: [AudioOutput] = []
    var currentOutput: UInt32?
    /// The name of the output macOS kept after a switch away from it, such as in-ear AirPods; `nil` when nothing needs saying.
    var keptOutput: String? {
        didSet {
            guard let keptOutput, keptOutput != oldValue else { return }
            NSAccessibility.post(
                element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: String(localized: "macOS kept the sound on \(keptOutput). Switch in System Settings › Sound instead.")]
            )
        }
    }
    /// Where the controls send what the user does, the one way in for every command.
    @ObservationIgnored private let dispatch: (AppAction) -> Void

    /// Picks the colours again when Increase Contrast changes, since the border it draws needs them even with the glow off.
    @ObservationIgnored private var contrastObserver: NSObjectProtocol?

    init(dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                self?.pickColours()
            }
        }
    }

    func send(_ command: PlaybackCommand) {
        dispatch(.command(command))
    }

    /// Plays the remembered track again.
    func resume() {
        dispatch(.resumeLast)
    }

    /// Brings the app that's playing to the front.
    func openApp() {
        dispatch(.openApp)
    }

    /// Brings the playing app to the front for a click on the notch, which does nothing while the notch is empty.
    func notchClicked() {
        dispatch(.notchClicked)
    }

    /// Opens the page of the artist that's playing, or the app when there isn't one to open.
    func openArtist() {
        dispatch(.openArtist)
    }

    func setVolume(_ volume: Double) {
        dispatch(.setVolume(volume))
    }

    func selectOutput(_ id: UInt32) {
        dispatch(.selectOutput(id))
    }

    /// Picks the colours off the main thread, then fades the glow to them.
    private func pickColours() {
        colourPicks += 1
        let pick = colourPicks
        guard let playback, showsGlow || matchesAlbumColour || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else {
            colours = nil
            return
        }
        let artwork = playback.artwork
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: playback.bundleIdentifier)
        Task { [weak self] in
            let colours = await Task.detached(priority: .utility) { () -> ArtworkColours? in
                if let artwork {
                    return ArtworkColours(data: artwork)
                }
                var rect = CGRect(x: 0, y: 0, width: 32, height: 32)
                guard let app, let icon = NSWorkspace.shared.icon(forFile: app.path).cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
                return ArtworkColours(image: icon)
            }.value
            guard let self, pick == self.colourPicks, colours != self.colours else { return }
            withAnimation(Native.glowChange) { self.colours = colours }
        }
    }
}
