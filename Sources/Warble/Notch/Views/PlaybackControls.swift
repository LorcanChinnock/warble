import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore
import WarbleModel

/// Previous, play or pause, and next in the middle, with shuffle and repeat either side when the app reports them.
struct PlaybackControls: View {
    let playback: PlaybackState
    let send: (PlaybackCommand) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Shuffle and repeat sit at the edges, over the middle three, so those stay centred whichever shows.
        ZStack {
            HStack(spacing: 12) {
                control("backward.fill", size: 16, nudge: -NotchMotion.pressNudge) { send(.previousTrack) }
                    .accessibilityLabel("Previous track")
                control(playback.isPlaying ? "pause.fill" : "play.fill", size: 22) { send(.togglePlayPause) }
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                control("forward.fill", size: 16, nudge: NotchMotion.pressNudge) { send(.nextTrack) }
                    .accessibilityLabel("Next track")
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
    private func control(_ symbol: String, size: CGFloat, on: Bool? = nil, nudge: CGFloat = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : Native.symbolSwap, value: symbol)
                .foregroundStyle(on == false ? AnyShapeStyle(Native.secondary) : AnyShapeStyle(.white))
                // A mode's symbol gives a small bounce when it changes, including repeat's change to "once".
                .symbolEffect(.bounce, options: .nonRepeating, value: on == nil || reduceMotion ? "" : "\(symbol)\(on == true)")
                .frame(width: 30, height: 30)
                .overlay(alignment: .bottom) {
                    ZStack {
                        if on == true {
                            Circle().fill(.white)
                                .frame(width: 3, height: 3)
                                .transition(reduceMotion ? .opacity : .scale(scale: NotchMotion.dotScale).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? Native.fade : Native.dotChange, value: on == true)
                    .padding(.bottom, 2)
                }
                .hoverWash(Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.notchPress(nudge: nudge))
    }
}
