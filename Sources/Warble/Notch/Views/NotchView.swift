import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

struct NotchView: View {
    let model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = model.state
        let size = model.size(state)
        let flare = NotchLayout.topCornerRadius(notch: model.notch)
        let shape = NotchShape(topRadius: flare, bottomRadius: Native.radius(state, notch: model.notch))
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
                .background { Glow(colours: colours) }
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

    var body: some View {
        Text("Nothing playing")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Native.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, notch.height)
    }
}

/// What an empty notch offers when it remembers a track and the pointer is on it: the art, dimmed so it reads as past,
/// the title and artist, and a button that plays it again. The button is there only while the app that played it is running.
private struct RecallContent: View {
    let notch: CGRect
    let player: PlayerModel

    var body: some View {
        if let track = player.lastPlayed {
            HStack(spacing: 10) {
                Artwork(image: player.lastArtwork, radius: 6, symbolSize: 18)
                    .frame(width: 40, height: 40)
                    .opacity(Native.dimmed)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Last played: \(track.title)"))
                Spacer(minLength: 0)
                if !NSRunningApplication.runningApplications(withBundleIdentifier: track.bundleIdentifier).isEmpty {
                    Button(action: player.resume) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .hoverWash(Circle())
                    }
                    .buttonStyle(.notch)
                    .accessibilityLabel(Text("Play \(track.title) again"))
                }
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .padding(.top, notch.height)
        }
    }
}
