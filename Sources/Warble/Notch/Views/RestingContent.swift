import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The art in the left wing and the play-state bars in the right, either side of the camera housing, each centred in a
/// square as tall as the housing. When a Doctor check fails, a "!" takes the bars' place, and with nothing playing it's
/// all that shows.
struct RestingContent: View {
    let playback: PlaybackState?
    let artwork: NSImage?
    let notch: CGRect
    let model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set once the wings appear, so the art grows and the bars rise as they slide out.
    @State private var appeared = false

    var body: some View {
        let wing = NotchLayout.wing(notch: notch)
        let art = wing - 2 * NotchLayout.inset(notch: notch)
        // Content on its way out still reads the model, so the bars drop as the notch leaves Resting. A toast or a lyric line keeps them.
        let isIn = appeared && (model.state == .resting || model.state == .toast || model.state == .lyrics)
        HStack(spacing: 0) {
            Group {
                if let playback {
                    Artwork(image: artwork, radius: art / 4, symbolSize: art / 2)
                        .frame(width: art, height: art)
                        // Grows into place as the wings slide out. With Reduce Motion it only fades.
                        .scaleEffect(isIn || reduceMotion ? 1 : NotchMotion.artScale)
                        .animation(isIn ? Native.artIn : Native.contentOut, value: isIn)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(nowPlaying(playback))
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityValue(playback.isPlaying ? Text("Playing") : Text("Paused"))
                }
            }
            .frame(width: wing)
            Spacer(minLength: 0)
            Group {
                if model.doctor.needsAttention {
                    AttentionButton(model: model, size: art)
                } else if let playback {
                    PlayStateBars(isPlaying: playback.isPlaying, isShown: isIn, reduceMotion: reduceMotion)
                        .frame(width: min(18, art), height: art * 0.6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: wing)
        }
        .frame(height: notch.height)
        .onAppear { appeared = true }
    }
}
