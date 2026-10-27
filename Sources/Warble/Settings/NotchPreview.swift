import SwiftUI
import WarbleCore
import WarbleModel

/// A made-up song for Settings to draw, never what's playing, so the page looks the same whether or not anything is.
enum NotchDemo {
    static let playback = PlaybackState(
        bundleIdentifier: "dev.lorcan.Warble.demo",
        title: "Slow Harbour",
        artist: "The Tidelines",
        duration: 200,
        elapsed: 76,
        elapsedTimestamp: Date(timeIntervalSince1970: 0),
        rate: 1
    )
    static let colours = ArtworkColours(
        first: .init(red: 0.88, green: 0.33, blue: 0.24),
        second: .init(red: 0.24, green: 0.42, blue: 0.88)
    )
}

/// A small screen with a virtual notch on it, drawn at the real notch's proportions with a made-up song. It rests as a
/// notch does, with the art, the bars and, when the setting is on, the title, and opens into the card when the pointer is
/// on it. A change to the pause or external-display setting pauses the song and, a beat later, ends it as those settings
/// would (`PreviewEnding`); it holds that end until the pointer leaves the preview, or another setting changes, then
/// plays again. Nothing else in it moves by itself.
struct NotchPreview: View {
    /// Whether the resting notch draws the title, which the Settings switch turns on.
    let showsTitle: Bool
    /// Whether the open card glows, which the Settings switch turns off.
    let showsGlow: Bool
    let pauseDelay: PauseDelay
    /// How big the open card is.
    let cardSize: CardSize
    /// With the virtual notch off there is none, so the screen is bare.
    let visibility: VirtualNotchVisibility
    @State private var isOpen = false
    /// Whether the pointer is on the preview, which opens it. A click then does nothing, so it can't close the card
    /// under the pointer; a press from the keyboard or VoiceOver, which have no pointer, toggles it.
    @State private var isHovering = false
    @State private var isPaused = false
    /// How the paused song ended, once the beat has passed.
    @State private var ending: PreviewEnding?
    /// Counts the pauses, so each one waits out its own beat.
    @State private var pauses = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let housing = CGRect(x: 0, y: 0, width: VirtualNotch.width, height: 24)

    var body: some View {
        let housing = Self.housing
        let showsNotch = visibility != .off && ending != .bareScreen
        let state: NotchState = ending == .emptyNotch ? (isOpen ? .note : .empty) : (isOpen ? .expanded : .resting)
        let size = NotchLayout.frame(state, notch: housing, cardSize: cardSize)?.size ?? housing.size
        let radius = Native.radius(state, notch: housing)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x2B3342), Color(hex: 0x1A1F29)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.black.opacity(0.3)).frame(height: housing.height).frame(maxHeight: .infinity, alignment: .top)
            Button {
                guard !isHovering else { return }
                isOpen.toggle()
            } label: {
                ZStack(alignment: .top) {
                    shape.fill(Native.panel)
                    // With Reduce Motion only the content fades; the shape changes at once, as the notch's does.
                    cardContent(NotchLayout.frame(.expanded, notch: housing)?.size ?? housing.size)
                        .scaleEffect(cardSize.scale, anchor: .top)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .opacity(state == .expanded ? 1 : 0)
                        .animation(Native.fade, value: state)
                    restingContent(housing)
                        .opacity(state == .resting ? 1 : 0)
                        .animation(Native.fade, value: state)
                    noteContent(NotchLayout.frame(.note, notch: housing)?.size ?? housing.size)
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
                isHovering = $0
                isOpen = $0
            }
            .accessibilityLabel(Text("Notch preview"))
            .accessibilityValue(isOpen ? Text("Open") : Text("Closed"))
            .accessibilityHint(Text("Shows how the notch looks, with a made-up song."))
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
        .clipShape(RoundedRectangle(cornerRadius: Native.groupRadius, style: .continuous))
        .onHover { inside in
            if !inside, isPaused { play() }
        }
        .onChange(of: pauseDelay) { pause() }
        .onChange(of: visibility) { pause() }
        .onChange(of: showsTitle) { play() }
        .onChange(of: showsGlow) { play() }
        .task(id: pauses) {
            guard isPaused, (try? await Task.sleep(for: PreviewEnding.beat)) != nil else { return }
            ending = PreviewEnding(pauseDelay: pauseDelay, visibility: visibility)
        }
    }

    /// Pauses the song, which ends a beat later. With the virtual notch off there's no notch to pause, so it plays.
    private func pause() {
        isOpen = false
        ending = nil
        isPaused = visibility != .off
        pauses += 1
    }

    private func play() {
        isPaused = false
        ending = nil
        pauses += 1
    }

    /// The art on the left and the bars on the right, either side of the housing, with the title between them when the
    /// setting is on.
    private func restingContent(_ housing: CGRect) -> some View {
        let wing = NotchLayout.wing(notch: housing)
        let art = wing - 2 * NotchLayout.inset(notch: housing)
        return HStack(spacing: 0) {
            DemoArt(radius: art / 4)
                .frame(width: art, height: art)
                .frame(width: wing)
            if showsTitle {
                VirtualTitle(playback: NotchDemo.playback, notch: housing)
            } else {
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 2) {
                ForEach([0.5, 1, 0.7, 0.4], id: \.self) { height in
                    Capsule().fill(.white).frame(width: 2, height: isPaused ? 2 : art * 0.6 * height)
                }
            }
            .animation(Native.fade, value: isPaused)
            .frame(width: wing)
        }
        .frame(width: NotchLayout.frame(.resting, notch: housing)?.width, height: housing.height)
    }

    /// The card, with the song's colours rising from its bottom corners like the real one's.
    private func cardContent(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DemoArt(radius: 8)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: NotchDemo.playback.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: NotchDemo.playback.artist ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Native.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Capsule().fill(Native.track).frame(height: 4)
                .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 0.38 * (size.width - 32), height: 4) }
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                Image(systemName: "backward.fill")
                Image(systemName: isPaused ? "play.fill" : "pause.fill").font(.title3)
                Image(systemName: "forward.fill")
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.housing.height + 6)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background { Glow(colours: NotchDemo.colours, showsGlow: showsGlow) }
        .accessibilityHidden(true)
    }

    /// What an empty notch says when the pointer is on it, as the real one does.
    private func noteContent(_ size: CGSize) -> some View {
        Text("Nothing playing")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Native.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Self.housing.height)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

/// The made-up song's art: its two colours, since the song has no picture.
private struct DemoArt: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(NotchDemo.colours.first), Color(NotchDemo.colours.second)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .accessibilityHidden(true)
    }
}

private extension Color {
    init(_ colour: ArtworkColours.RGB) {
        self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue)
    }
}
