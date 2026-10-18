import AppKit
import SwiftUI
import WarbleCore

/// What the notch view draws. `NotchController` changes `state` inside an animation, and the view morphs to it.
@MainActor
@Observable
final class NotchModel {
    var state = NotchState.hidden
    /// The camera housing, which every state's shape is measured from.
    var notch = CGRect.zero
    var playback: PlaybackState? {
        didSet {
            if playback?.artwork != oldValue?.artwork {
                artwork = playback?.artwork.flatMap(NSImage.init(data:))
            }
        }
    }
    private(set) var artwork: NSImage?
    @ObservationIgnored var onClick: () -> Void = {}

    func size(_ state: NotchState) -> CGSize {
        NotchLayout.frame(state, notch: notch)?.size ?? .zero
    }
}

struct NotchView: View {
    let model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = model.state
        let size = model.size(state)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Native.radius(state), bottomTrailingRadius: Native.radius(state))
        ZStack(alignment: .top) {
            shape
                .fill(Native.panel)
                .frame(width: size.width, height: size.height)
                .transaction(snapWithReduceMotion)
            // Each state's content keeps its own size while the shape morphs, so it fades rather than reflows.
            NotchContent(state: state, playback: model.playback, artwork: model.artwork, notchHeight: model.notch.height)
                .frame(width: size.width, height: size.height, alignment: .top)
                .id(state)
                .transition(.opacity)
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

private struct NotchContent: View {
    let state: NotchState
    let playback: PlaybackState?
    let artwork: NSImage?
    let notchHeight: CGFloat

    var body: some View {
        switch (state, playback) {
        case (.peek, let playback?):
            PeekContent(playback: playback)
                .padding(.top, notchHeight)
        case (.expanded, let playback?):
            ExpandedContent(playback: playback, artwork: artwork)
                .padding(.top, notchHeight)
        default:
            // Empty until the art and play-state bars arrive (#19), so there's nothing to read yet.
            Color.clear.accessibilityHidden(true)
        }
    }
}

/// The title and artist under the notch, and how far through the track it is.
private struct PeekContent: View {
    let playback: PlaybackState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Marquee(text: playback.title, font: .system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let artist = playback.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Native.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            ProgressLine(playback: playback)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 7)
    }
}

/// The full card: art, title, artist and album, with room below for the controls (#11).
private struct ExpandedContent: View {
    let playback: PlaybackState
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Artwork(image: artwork)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Group {
                    if let artist = playback.artist { Text(artist) }
                    if let album = playback.album { Text(album) }
                }
                .font(.system(size: 13))
                .foregroundStyle(Native.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct Artwork: View {
    let image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                shape.fill(Color(white: 0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(Native.secondary)
                    }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// A thin line filled as far as the track has played. It redraws only while it's on screen and playing.
private struct ProgressLine: View {
    let playback: PlaybackState

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !playback.isPlaying)) { context in
            let fraction = playback.duration.map { $0 > 0 ? playback.elapsed(at: context.date) / $0 : 0 } ?? 0
            Capsule()
                .fill(Color.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule().fill(.white).frame(width: geometry.size.width * fraction)
                    }
                }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// One line of text that scrolls when it's too long to fit, and is cut short instead while Reduce Motion is on.
private struct Marquee: View {
    let text: String
    let font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var available: CGFloat = 0
    @State private var needed: CGFloat = 0
    @State private var offset: CGFloat = 0

    private static let gap: CGFloat = 32
    /// Points per second.
    private static let speed: CGFloat = 30

    private var scrolls: Bool { !reduceMotion && needed > available }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(scrolls ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { available = $0 }
            .background {
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { needed = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    HStack(spacing: Self.gap) {
                        Text(text)
                        Text(text)
                    }
                    .font(font)
                    .fixedSize()
                    .offset(x: offset)
                    .accessibilityHidden(true)
                }
            }
            .clipped()
            .accessibilityLabel(text)
            .onChange(of: scrolls, initial: true) { _, scrolls in
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { offset = 0 }
                guard scrolls else { return }
                let distance = needed + Self.gap
                withAnimation(.linear(duration: distance / Self.speed).delay(1.5).repeatForever(autoreverses: false)) {
                    offset = -distance
                }
            }
    }
}
