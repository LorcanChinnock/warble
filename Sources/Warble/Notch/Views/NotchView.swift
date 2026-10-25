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
                // A virtual housing has no camera to hide behind, so there Idle draws nothing, though it still takes the
                // pointer, unless its display is set to show a notch always.
                .opacity(state == .idle && model.isVirtual && !model.isAlwaysShown ? 0 : 1)
                .transaction(snapWithReduceMotion)
            // Each state's content keeps its own size while the shape morphs, so it fades rather than reflows. What it
            // shows is passed in, so content on its way out keeps the track that stopped rather than going blank.
            // While Idle, the player still holds the paused track, which only the idle card shows.
            let playback = model.isPlaying ? model.player.playback : nil
            NotchContent(state: state, card: model.card, playback: playback, artwork: model.player.artwork, colours: model.player.colours, model: model)
                .frame(width: size.width, height: size.height, alignment: .top)
                .id(ContentID(
                    state: state == .toast || state == .lyrics ? .resting : state, card: model.card, isPlaying: playback != nil,
                    activity: state == .activity ? model.activities.first?.key : nil
                ))
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

/// Tells one state's content from the next, so a change of card, such as resuming from the idle card, or a track
/// starting beside the "!", fades too. A toast or a lyric line is Resting's content with a strip below, so the wings
/// stay put while only the strip comes and goes.
private struct ContentID: Hashable {
    let state: NotchState
    let card: NotchCard
    let isPlaying: Bool
    /// The activity in the wings, so a different one takes them with a fade.
    let activity: ActivityKey?
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
    let card: NotchCard
    let playback: PlaybackState?
    let artwork: NSImage?
    let colours: ArtworkColours?
    let model: NotchModel

    var body: some View {
        switch (state, card, playback) {
        case (.activity, _, _):
            if let activity = model.activities.first {
                ActivityWings(activity: activity, notch: model.notch)
            }
        case (.expanded, .player, let playback?):
            // The rows go below the controls, which keep the card's own height, so nothing moves under the pointer.
            VStack(spacing: 0) {
                ExpandedContent(playback: playback, artwork: artwork, model: model)
                    .frame(height: NotchLayout.expandedDrop)
                ActivityRows(model: model)
            }
                .padding(.top, model.notch.height)
                .background { Glow(colours: colours) }
        case (.expanded, .doctor, _):
            DoctorCard(model: model)
                .padding(.top, model.notch.height)
        case (.expanded, .lyrics, _):
            if let lyrics = model.lyrics {
                VStack(spacing: 0) {
                    LyricsCard(lyrics: lyrics, model: model)
                        .frame(height: NotchLayout.expandedDrop)
                    ActivityRows(model: model)
                }
                .padding(.top, model.notch.height)
                    .background { Glow(colours: colours) }
            }
        case (.expanded, .activity, _):
            ActivityCard(model: model)
                .padding(.top, model.notch.height)
        case (.expanded, .idle, _):
            IdleCard(model: model)
                .padding(.top, model.notch.height)
        case (.resting, _, let playback?), (.toast, _, let playback?), (.lyrics, _, let playback?):
            VStack(spacing: 0) {
                RestingContent(playback: playback, artwork: artwork, notch: model.notch, model: model)
                if state == .toast, let toast = model.toast {
                    ToastLines(toast: toast)
                        // A skip while it shows swaps the words with a fade.
                        .id(toast)
                        .transition(ContentTransition())
                } else if state == .lyrics, let lyric = model.lyric {
                    LyricsLine(text: lyric)
                        // Each line fades in as the last fades out.
                        .id(lyric)
                        .transition(ContentTransition())
                }
            }
        case (.hint, _, _):
            VStack(spacing: 0) {
                Color.clear.frame(height: model.notch.height)
                DemoHint()
            }
        case (.resting, _, nil):
            RestingContent(playback: nil, artwork: nil, notch: model.notch, model: model)
        default:
            Color.clear.accessibilityHidden(true)
        }
    }
}
