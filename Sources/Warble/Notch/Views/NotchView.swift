import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleModel
import WarbleCore

struct NotchView: View {
    let model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = model.state
        let size = model.size(state)
        let flare = NotchLayout.topCornerRadius(notch: model.notch, shape: model.shape)
        let radius = Native.radius(state, notch: model.notch, shape: model.shape)
        // A pill's top corners are as round as its bottom ones, since nothing joins it to the screen's edge.
        let shape = NotchShape(topRadius: flare, bottomRadius: radius, roundTop: model.shape == .pill ? radius : 0)
        ZStack(alignment: .top) {
            shape
                .fill(Native.panel)
                .frame(width: size.width + 2 * flare, height: size.height)
                .transaction(snapWithReduceMotion)
            // Each state's content keeps its own size while the shape morphs, so it fades rather than reflows. What it
            // shows is passed in, so content on its way out keeps the track that stopped rather than going blank.
            // Once nothing is playing, the player still holds the paused track, which nothing shows.
            let playback = model.isPlaying ? model.player.playback : nil
            NotchContent(state: state, playback: playback, artwork: model.player.artwork, colours: model.player.colours, model: model)
                .frame(width: size.width, height: size.height, alignment: .top)
                .id(ContentID(state: state, isPlaying: playback != nil))
                .transition(ContentTransition())
        }
        .mask(alignment: .top) {
            shape
                .frame(width: size.width + 2 * flare, height: size.height)
                .transaction(snapWithReduceMotion)
        }
        .contentShape(shape)
        .onTapGesture { model.player.notchClicked() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// With Reduce Motion the shape and its mask change at once, and only the content fades.
    private func snapWithReduceMotion(_ transaction: inout Transaction) {
        if reduceMotion {
            transaction.animation = nil
        }
    }
}

/// Tells one state's content from the next, so a track starting or stopping under the same state fades too.
private struct ContentID: Hashable {
    let state: NotchState
    let isPlaying: Bool
}

/// How a state's content comes and goes while the shape morphs: in a moment after the shape starts to grow, so the shape
/// uncovers it, and out quickly, before the shape closes over it.
private struct ContentTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .animation(phase.isIdentity ? Native.contentIn : Native.contentOut, value: phase)
    }
}

private struct NotchContent: View {
    let state: NotchState
    let playback: PlaybackState?
    let artwork: NSImage?
    let colours: ArtworkColours?
    let model: NotchModel

    private var standard: CGSize {
        NotchLayout.frame(.expanded, notch: model.notch)?.size ?? model.notch.size
    }

    var body: some View {
        switch (state, playback) {
        case (.note, _):
            NoteContent(notch: model.notch)
        case (.recall, _):
            RecallContent(notch: model.notch, player: model.player)
        case (.expanded, let playback?):
            // Laid out at the standard size and scaled, so every size has the same card.
            ExpandedContent(playback: playback, artwork: artwork, model: model)
                .padding(.top, model.notch.height)
                .background { Glow(colours: colours, isPlaying: playback.isPlaying) }
                .frame(width: standard.width, height: standard.height, alignment: .top)
                .scaleEffect(model.cardSize.scale, anchor: .top)
        case (.resting, let playback?):
            RestingContent(playback: playback, artwork: artwork, notch: model.notch, model: model)
        default:
            Color.clear.accessibilityHidden(true)
        }
    }
}

/// What an empty notch says when the pointer is on it: one line under the housing, with no controls.
struct NoteContent: View {
    let notch: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    var body: some View {
        Text("Nothing playing")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Native.secondary)
            .offset(y: risen || reduceMotion ? 0 : NotchMotion.riseDistance)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, notch.height)
            .onAppear { rise($risen, reduceMotion: reduceMotion, index: 0) }
    }
}

/// What an empty notch offers when it remembers a track and the pointer is on it: the art, dimmed so it reads as past,
/// the title and artist, and a play icon. The whole card plays the track again. It's only offered while the app still
/// holds the track, since `reduce` forgets it once the source stops reporting.
private struct RecallContent: View {
    let notch: CGRect
    let player: PlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether each part (art, text, play icon) has risen into place yet.
    @State private var risen = [false, false, false]
    @State private var hovering = false

    var body: some View {
        if let track = player.lastPlayed {
            Button(action: player.resume) {
                HStack(spacing: 10) {
                    Artwork(image: player.lastArtwork, radius: 6, symbolSize: 18)
                        .frame(width: 40, height: 40)
                        .opacity(Native.dimmed)
                        .offset(y: lift(0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(Font(Native.titleFont(player.notchFont, size: 13, weight: .semibold)))
                            .foregroundStyle(player.tint.map(Color.init(nsColor:)) ?? .white)
                            .lineLimit(1)
                        if let artist = track.artist {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundStyle(Native.secondary)
                                .lineLimit(1)
                        }
                    }
                    .offset(y: lift(1))
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        // White like the player's other controls: without a colour it takes the label colour, which is
                        // black in Light mode and so vanishes on the black notch.
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .scaleEffect(hovering && !reduceMotion ? NotchMotion.playHoverScale : 1)
                        .animation(Native.playHover, value: hovering)
                        .offset(y: lift(2))
                }
                .onHover { hovering = $0 }
                .onAppear { for index in risen.indices { rise($risen[index], reduceMotion: reduceMotion, index: index) } }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .hoverWash(Rectangle())
            }
            .buttonStyle(.notch)
            .accessibilityLabel(Text("Play \(track.title) again"))
            .padding(.top, notch.height)
        }
    }
}

/// Starts a rise into place for the part at `index` of a card that has just appeared, or does nothing but show it with
/// Reduce Motion, since the card's own fade is all that moves then.
@MainActor private func rise(_ risen: Binding<Bool>, reduceMotion: Bool, index: Int) {
    guard !reduceMotion else { risen.wrappedValue = true; return }
    withAnimation(Native.rise(delay: NotchMotion.recallDelay(index))) { risen.wrappedValue = true }
}

extension RecallContent {
    /// How far below its place the part at `index` is, until it has risen.
    fileprivate func lift(_ index: Int) -> CGFloat {
        risen[index] || reduceMotion ? 0 : NotchMotion.riseDistance
    }
}
