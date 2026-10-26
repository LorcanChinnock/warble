import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// What's playing and the controls for it, which every display's notch shows. The artwork is decoded and its colours
/// picked once, however many notches there are.
@MainActor
@Observable
final class PlayerModel {
    /// The last track played, which the idle card shows. It outlasts what's playing, and Warble too.
    var lastPlayed: LastPlayed? {
        didSet {
            if lastPlayed?.artwork != oldValue?.artwork {
                lastPlayedArtwork = lastPlayed?.artwork.flatMap(NSImage.init(data:))
            }
        }
    }
    private(set) var lastPlayedArtwork: NSImage?
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
    /// The glow's colours, from the artwork or, without it, the app's icon.
    private(set) var colours: ArtworkColours?
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
    /// Where the controls send what the user does, the one way in for every command.
    @ObservationIgnored private let dispatch: (AppAction) -> Void

    init(dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
    }

    func send(_ command: PlaybackCommand) {
        dispatch(.command(command))
    }

    /// Back or forward by `seconds` through a podcast or audiobook.
    func skip(by seconds: TimeInterval) {
        dispatch(.skip(by: seconds))
    }

    /// Brings the app that's playing to the front, or while Idle the one that played last.
    func openApp() {
        dispatch(.openApp)
    }

    /// Plays the last track again from the idle card.
    func resumeLastPlayed() {
        dispatch(.resumeLastPlayed)
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
        guard let playback else {
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
