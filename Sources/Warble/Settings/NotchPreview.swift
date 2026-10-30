import AppKit
import SwiftUI
import WarbleCore
import WarbleModel

/// A made-up song for the preview to draw while nothing is playing, so the page looks the same whether or not anything is.
enum NotchDemo {
    /// Two colours across the square, since the song has no picture of its own.
    static let artwork: Data? = {
        let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(
                starting: NSColor(srgbRed: 0.88, green: 0.33, blue: 0.24, alpha: 1),
                ending: NSColor(srgbRed: 0.24, green: 0.42, blue: 0.88, alpha: 1)
            )?.draw(in: rect, angle: 315)
            return true
        }
        return image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }()

    static func playback(since start: Date) -> PlaybackState {
        PlaybackState(
            bundleIdentifier: "dev.lorcan.Warble.demo",
            title: "Slow Harbour",
            artist: "The Tidelines",
            album: "Low Tide",
            duration: 200,
            elapsed: 76,
            elapsedTimestamp: start,
            rate: 1,
            artwork: artwork
        )
    }
}

/// What the preview owns to draw the real views: a player and a notch model that are never wired to the app, so pressing
/// a control in the preview does nothing.
@MainActor
final class PreviewNotch {
    let player = PlayerModel { _ in }
    let model: NotchModel

    init() {
        model = NotchModel(player: player)
    }
}

/// A small screen with a virtual notch on it, drawn at the real notch's proportions from the real views
/// (`RestingContent`, `ExpandedContent`), with the song that's playing or, when nothing is, a made-up one. It rests as a
/// notch does, with the art, the bars and, when the setting is on, the title, and opens into the card when the pointer is
/// on it; its controls do nothing. A change to the title font or card size opens it for a couple of seconds to show the
/// change, unless Reduce Motion is on. A change to the pause or external-display setting pauses the song and, a beat
/// later, ends it as those settings would (`PreviewEnding`); it holds that end until the pointer leaves the preview, or
/// another setting changes, then plays again. Nothing else in it moves by itself.
struct NotchPreview: View {
    /// Whether the resting notch draws the title, which the Settings switch turns on.
    let showsTitle: Bool
    /// The face of the title, which Settings chooses.
    let notchFont: NotchFont
    let pauseDelay: PauseDelay
    /// How big the open card is.
    let cardSize: CardSize
    /// With the virtual notch off there is none, so the screen is bare.
    let visibility: VirtualNotchVisibility
    /// While the page scrolls under the pointer, the preview stays as it is rather than opening mid-scroll.
    let isScrolling: Bool
    @Environment(PlayerModel.self) private var live
    @State private var preview = PreviewNotch()
    /// When the made-up song started, which its position runs on from.
    @State private var startedAt = Date.now
    @State private var isOpen = false
    /// Whether the pointer is on the preview, which opens it. A click then does nothing, so it can't close the card
    /// under the pointer; a press from the keyboard or VoiceOver, which have no pointer, toggles it.
    @State private var isHovering = false
    @State private var isPaused = false
    /// When the song was paused, which it holds its position at.
    @State private var pausedAt = Date.now
    /// How the paused song ended, once the beat has passed.
    @State private var ending: PreviewEnding?
    /// Counts the pauses, so each one waits out its own beat.
    @State private var pauses = 0
    /// Counts the changes that open the card, so each one closes it after its own wait.
    @State private var peeks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the preview shows: the song that's playing, or the made-up one, held where it was when the song is paused.
    private var song: PlaybackState {
        let song = live.showsPlayback ? live.playback : nil
        let shown = song ?? NotchDemo.playback(since: startedAt)
        return isPaused ? shown.playing(false, at: pausedAt) : shown
    }

    private static let housing = CGRect(x: 0, y: 0, width: VirtualNotch.width, height: 24)

    var body: some View {
        let housing = Self.housing
        let showsNotch = visibility != .off && ending != .bareScreen
        let state: NotchState = ending == .emptyNotch ? (isOpen ? .note : .empty) : (isOpen ? .expanded : .resting)
        let size = NotchLayout.frame(state, notch: housing, cardSize: cardSize)?.size ?? housing.size
        let radius = Native.radius(state, notch: housing)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        ZStack(alignment: .top) {
            Warm.wallpaper
            Rectangle().fill(.white.opacity(0.3)).frame(height: housing.height).frame(maxHeight: .infinity, alignment: .top)
            Button {
                guard !isHovering else { return }
                isOpen.toggle()
            } label: {
                ZStack(alignment: .top) {
                    shape.fill(Native.panel)
                    // With Reduce Motion only the content fades; the shape changes at once, as the notch's does.
                    // Only while open, so its scrubber's timeline isn't ticking behind a closed notch.
                    ZStack {
                        if state == .expanded {
                            cardContent(song)
                                .scaleEffect(cardSize.scale, anchor: .top)
                                .frame(width: size.width, height: size.height, alignment: .top)
                                .transition(.opacity)
                        }
                    }
                    .animation(Native.fade, value: state)
                    RestingContent(playback: song, artwork: preview.player.artwork, notch: housing, model: preview.model)
                        .frame(width: NotchLayout.frame(.resting, notch: housing)?.width)
                        .allowsHitTesting(false)
                        .opacity(state == .resting ? 1 : 0)
                        .animation(Native.fade, value: state)
                    NoteContent(notch: housing)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .opacity(state == .note ? 1 : 0)
                        .animation(Native.fade, value: state)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .mask(alignment: .top) { shape.frame(width: size.width, height: size.height) }
                .animation(reduceMotion ? nil : Native.morph, value: state)
                .contentShape(shape)
            }
            .buttonStyle(.notch)
            .onHover {
                isHovering = $0 && !isScrolling
                isOpen = $0 && !isScrolling
            }
            .accessibilityLabel(Text("Notch preview"))
            .accessibilityValue(isOpen ? Text("Open") : Text("Closed"))
            .accessibilityHint(Text("Shows how the notch looks."))
            // Faded rather than moved, so nothing animates under Reduce Motion.
            .opacity(showsNotch ? 1 : 0)
            .animation(Native.fade, value: showsNotch)
            .allowsHitTesting(showsNotch)
            .accessibilityHidden(!showsNotch)
            .onChange(of: showsNotch) {
                isOpen = false
                isHovering = false
            }
        }
        .frame(height: 232)
        .clipShape(RoundedRectangle(cornerRadius: Warm.cardRadius, style: .continuous))
        .onHover { inside in
            if !inside, isPaused { play() }
        }
        .onChange(of: Inputs(song: song, state: state, showsTitle: showsTitle, cardSize: cardSize, notchFont: notchFont, volume: live.volume, isMuted: live.isMuted, outputs: live.outputs, currentOutput: live.currentOutput), initial: true) { feed(state: state) }
        .onChange(of: isOpen) { if isOpen { startedAt = .now } }
        .onChange(of: pauseDelay) { pause() }
        .onChange(of: visibility) { pause() }
        .onChange(of: showsTitle) { play() }
        .onChange(of: notchFont) { peek() }
        .onChange(of: cardSize) { peek() }
        .task(id: pauses) {
            guard isPaused, (try? await Task.sleep(for: PreviewEnding.beat)) != nil else { return }
            ending = PreviewEnding(pauseDelay: pauseDelay, visibility: visibility)
        }
        .task(id: peeks) {
            guard peeks > 0, (try? await Task.sleep(for: Self.peekLength)) != nil, !isHovering else { return }
            isOpen = false
        }
    }

    /// How long a change that opens the card leaves it open, unless the pointer is on it.
    private static let peekLength: Duration = .seconds(2)

    /// What the real views read, which changes the preview's own player and model rather than the app's.
    private struct Inputs: Equatable {
        let song: PlaybackState
        let state: NotchState
        let showsTitle: Bool
        let cardSize: CardSize
        let notchFont: NotchFont
        let volume: Double?
        let isMuted: Bool
        let outputs: [AudioOutput]
        let currentOutput: UInt32?
    }

    private func feed(state: NotchState) {
        let player = preview.player
        player.playback = song
        player.notchFont = notchFont
        player.volume = live.volume ?? 0.6
        player.isMuted = live.isMuted
        player.outputs = live.outputs
        player.currentOutput = live.currentOutput
        let model = preview.model
        model.notch = Self.housing
        model.state = state
        model.showsTitle = showsTitle
        model.cardSize = cardSize
        model.isPlaying = true
    }

    /// Plays the song and opens the card to show a change to it, which is left open a moment. Under Reduce Motion nothing
    /// opens by itself, and with the virtual notch off there is no notch to open.
    private func peek() {
        play()
        guard !reduceMotion, visibility != .off else { return }
        isOpen = true
        peeks += 1
    }

    /// Pauses the song, which ends a beat later. With the virtual notch off there's no notch to pause, so it plays.
    private func pause() {
        isOpen = false
        ending = nil
        pausedAt = .now
        isPaused = visibility != .off
        pauses += 1
    }

    private func play() {
        isPaused = false
        ending = nil
        pauses += 1
    }

    /// The card, with the song's colours rising from its bottom corners like the real one's, laid out at the standard size.
    private func cardContent(_ song: PlaybackState) -> some View {
        let standard = NotchLayout.frame(.expanded, notch: Self.housing)?.size ?? Self.housing.size
        return ExpandedContent(playback: song, artwork: preview.player.artwork, model: preview.model)
            .padding(.top, Self.housing.height)
            .background { Glow(colours: preview.player.colours) }
            .frame(width: standard.width, height: standard.height, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
