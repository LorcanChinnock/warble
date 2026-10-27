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
/// on it. Nothing in it moves by itself, so it sets no timers.
struct NotchPreview: View {
    /// Whether the resting notch draws the title, which the Settings switch turns on.
    let showsTitle: Bool
    @State private var isOpen = false
    /// Whether the pointer is on the preview, which opens it. A click then does nothing, so it can't close the card
    /// under the pointer; a press from the keyboard or VoiceOver, which have no pointer, toggles it.
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let housing = CGRect(x: 0, y: 0, width: VirtualNotch.width, height: 24)

    var body: some View {
        let housing = Self.housing
        let resting = NotchLayout.frame(.resting, notch: housing)?.size ?? housing.size
        let expanded = NotchLayout.frame(.expanded, notch: housing)?.size ?? housing.size
        let size = isOpen ? expanded : resting
        let radius = isOpen ? Native.expandedRadius : NotchLayout.cornerRadius(notch: housing)
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
                    cardContent(expanded)
                        .opacity(isOpen ? 1 : 0)
                        .animation(Native.fade, value: isOpen)
                    restingContent(housing)
                        .opacity(isOpen ? 0 : 1)
                        .animation(Native.fade, value: isOpen)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .mask(alignment: .top) { shape.frame(width: size.width, height: size.height) }
                .animation(reduceMotion ? nil : Native.morph, value: isOpen)
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
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Native.groupRadius, style: .continuous))
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
                    Capsule().fill(.white).frame(width: 2, height: art * 0.6 * height)
                }
            }
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
                Image(systemName: "pause.fill").font(.title3)
                Image(systemName: "forward.fill")
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.housing.height + 6)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background { Glow(colours: NotchDemo.colours) }
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
