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
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Native.radius(state, notch: model.notch), bottomTrailingRadius: Native.radius(state, notch: model.notch))
        ZStack(alignment: .top) {
            shape
                .fill(Native.panel)
                .frame(width: size.width, height: size.height)
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
                .frame(width: size.width, height: size.height)
                .transaction(snapWithReduceMotion)
        }
        .contentShape(shape)
        .onTapGesture { model.onClick() }
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

    var body: some View {
        switch (state, playback) {
        case (.expanded, let playback?):
            ExpandedContent(playback: playback, artwork: artwork, model: model)
                .padding(.top, model.notch.height)
                .background { Glow(colours: colours) }
        case (.resting, let playback?):
            RestingContent(playback: playback, artwork: artwork, notch: model.notch, model: model)
        default:
            Color.clear.accessibilityHidden(true)
        }
    }
}
