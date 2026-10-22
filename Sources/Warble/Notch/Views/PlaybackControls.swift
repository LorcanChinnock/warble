import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// Previous, play or pause, and next in the middle, with shuffle and repeat either side when the app reports them. A
/// podcast or audiobook (`skipsBySeconds`) has back 15 and forward 30 seconds where a song has previous and next.
struct PlaybackControls: View {
    let playback: PlaybackState
    let skipsBySeconds: Bool
    let send: (PlaybackCommand) -> Void
    let skip: (TimeInterval) -> Void

    var body: some View {
        // Shuffle and repeat sit at the edges, over the middle three, so those stay centred whichever shows.
        ZStack {
            HStack(spacing: 12) {
                if skipsBySeconds {
                    control("gobackward.15", size: 17) { skip(-SpokenWord.back) }
                        .accessibilityLabel("Back 15 seconds")
                } else {
                    control("backward.fill", size: 16) { send(.previousTrack) }
                        .accessibilityLabel("Previous track")
                }
                control(playback.isPlaying ? "pause.fill" : "play.fill", size: 22) { send(.togglePlayPause) }
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                if skipsBySeconds {
                    control("goforward.30", size: 17) { skip(SpokenWord.forward) }
                        .accessibilityLabel("Forward 30 seconds")
                } else {
                    control("forward.fill", size: 16) { send(.nextTrack) }
                        .accessibilityLabel("Next track")
                }
            }
            HStack(spacing: 0) {
                if let shuffle = playback.shuffle {
                    control("shuffle", size: 13, on: shuffle != .off) { send(.setShuffle(shuffle.next)) }
                        .accessibilityLabel("Shuffle")
                        .accessibilityValue(shuffle == .off ? "Off" : "On")
                }
                Spacer(minLength: 0)
                if let repeatMode = playback.repeatMode {
                    control(repeatMode == .one ? "repeat.1" : "repeat", size: 13, on: repeatMode != .off) { send(.setRepeat(repeatMode.next)) }
                        .accessibilityLabel("Repeat")
                        .accessibilityValue(repeatMode == .off ? "Off" : repeatMode == .one ? "One" : "All")
                }
            }
        }
    }

    /// A white symbol on a target at least 30 points square. A mode that's on (`on`) is white with a dot under it, and one
    /// that's off grey without, so the dot says which, not only the colour.
    private func control(_ symbol: String, size: CGFloat, on: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(on == false ? AnyShapeStyle(Native.secondary) : AnyShapeStyle(.white))
                .frame(width: 30, height: 30)
                .overlay(alignment: .bottom) {
                    if on == true {
                        Circle().fill(.white)
                            .frame(width: 3, height: 3)
                            .padding(.bottom, 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.notch)
    }
}
