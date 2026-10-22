import Foundation
import WarbleCore

/// A track that plays without a player, for `-notchPreviewState resting`. Next and previous change its title, such as
/// from a shortcut, to show the track-change toast; other commands only change what the notch shows.
@MainActor
final class PreviewSource: NowPlayingSource {
    let states: AsyncStream<PlaybackState?>
    private let continuation: AsyncStream<PlaybackState?>.Continuation
    /// What the notch shows now, which a guess at play/pause may have changed.
    private let current: () -> PlaybackState?
    private var track = 1

    init(current: @escaping () -> PlaybackState?) {
        (states, continuation) = AsyncStream.makeStream()
        self.current = current
        continuation.yield(PlaybackState(
            bundleIdentifier: "com.apple.Music",
            title: "Preview track with a title long enough to scroll",
            artist: "Preview artist",
            album: "Preview album",
            duration: 240,
            elapsed: 60,
            elapsedTimestamp: .now,
            rate: 1,
            shuffle: .off,
            repeatMode: .off
        ))
    }

    func send(_ command: PlaybackCommand) async {
        guard var playback = current() else { return }
        switch command {
        case .nextTrack: track += 1
        case .previousTrack: track = max(track - 1, 1)
        default: return
        }
        playback.title = "Preview track \(track) with a title long enough to scroll"
        continuation.yield(playback)
    }
}
