import SwiftUI
import WarbleCore

/// How VoiceOver names what's playing: "Now playing: Song by Artist".
func nowPlaying(_ playback: PlaybackState) -> Text {
    playback.artist.map { Text("Now playing: \(playback.title) by \($0)") } ?? Text("Now playing: \(playback.title)")
}
