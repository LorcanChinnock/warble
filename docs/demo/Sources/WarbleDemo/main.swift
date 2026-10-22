import AppKit
import MediaPlayer

/// Publishes a fixed playlist to macOS as now-playing information and answers the media keys and Warble's buttons, so
/// Warble reads it through the adapter like any other app. It plays no sound.
@MainActor
final class Player {
    private let tracks = Track.all
    private var index = 0
    private var position: TimeInterval = 0
    private var playing = true
    private var startedAt = Date()
    private var artwork: [MPMediaItemArtwork]

    init() {
        artwork = tracks.map(Player.makeArtwork)
    }

    /// Not main-actor: the system asks for the image from its own queue.
    private nonisolated static func makeArtwork(_ track: Track) -> MPMediaItemArtwork {
        let image = track.artwork()
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func start(paused: Bool, track: Int) {
        index = min(max(track, 0), tracks.count - 1)
        playing = !paused
        publish()
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { _ in Player.run { $0.playing = true } }
        commands.pauseCommand.addTarget { _ in Player.run { $0.playing = false } }
        commands.togglePlayPauseCommand.addTarget { _ in Player.run { $0.playing.toggle() } }
        commands.nextTrackCommand.addTarget { _ in Player.run { $0.move(1) } }
        commands.previousTrackCommand.addTarget { _ in Player.run { $0.move(-1) } }
        commands.changePlaybackPositionCommand.addTarget { event in
            let time = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            return Player.run { $0.position = time }
        }
    }

    static let shared = Player()

    /// Runs a command on the main actor, since the command center calls from elsewhere.
    private nonisolated static func run(_ change: @MainActor (Player) -> Void) -> MPRemoteCommandHandlerStatus {
        MainActor.assumeIsolated {
            shared.settle()
            change(shared)
            shared.publish()
        }
        return .success
    }

    /// Brings `position` up to now before a change, as a player's clock would.
    private func settle() {
        if playing { position += Date().timeIntervalSince(startedAt) }
        startedAt = Date()
    }

    private func move(_ step: Int) {
        index = (index + step + tracks.count) % tracks.count
        position = 0
    }

    private func publish() {
        startedAt = Date()
        let track = tracks[index]
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPMediaItemPropertyArtwork: artwork[index],
        ]
        center.playbackState = playing ? .playing : .paused
    }
}

// --track N starts on the Nth track (1 to 4). --paused starts paused.
let arguments = CommandLine.arguments
let track = arguments.firstIndex(of: "--track").flatMap { Int(arguments[$0 + 1]) } ?? 1
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Player.shared.start(paused: arguments.contains("--paused"), track: track - 1)
app.run()
