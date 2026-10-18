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
            if playback?.bundleIdentifier != oldValue?.bundleIdentifier {
                appName = playback.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).first?.localizedName }
            }
        }
    }
    private(set) var artwork: NSImage?
    /// The name of the app that's playing, for VoiceOver.
    private(set) var appName: String?
    @ObservationIgnored var onClick: () -> Void = {}
    @ObservationIgnored var onCommand: (PlaybackCommand) -> Void = { _ in }
    /// Brings the app that's playing to the front.
    @ObservationIgnored var onOpenApp: () -> Void = {}
    /// The output's volume from 0 to 1, read while Expanded shows; `nil` when it can't be changed.
    var volume: Double?
    var isMuted = false
    @ObservationIgnored var onVolume: (Double) -> Void = { _ in }

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
            NotchContent(state: state, model: model)
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
    let model: NotchModel

    var body: some View {
        switch (state, model.playback) {
        case (.peek, let playback?):
            PeekContent(playback: playback)
                .padding(.top, model.notch.height)
        case (.expanded, let playback?):
            ExpandedContent(playback: playback, model: model)
                .padding(.top, model.notch.height)
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

/// The full card: art, title, artist and album, then the position and the controls.
private struct ExpandedContent: View {
    let playback: PlaybackState
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.onOpenApp) {
                    Artwork(image: model.artwork)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.appName.map { Text("Open \($0)") } ?? Text("Open the app that's playing"))
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
            Spacer(minLength: 0)
            Scrubber(playback: playback) { model.onCommand(.seek(to: $0)) }
            Spacer(minLength: 0)
            PlaybackControls(playback: playback, send: model.onCommand)
            if let volume = model.volume {
                Spacer(minLength: 0)
                VolumeSlider(volume: model.isMuted ? 0 : volume, isMuted: model.isMuted, set: model.onVolume)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// The elapsed and remaining time either side of a bar that seeks where it's released. While dragging, the bar and the
/// time follow the pointer and nothing is sent; a live stream, which has no end, shows only the elapsed time.
private struct Scrubber: View {
    let playback: PlaybackState
    let seek: (TimeInterval) -> Void
    /// The position the pointer is dragging to, as a fraction of the track.
    @State private var dragged: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !playback.isPlaying || dragged != nil)) { context in
            let duration = playback.duration ?? 0
            let position = dragged.map { $0 * duration } ?? playback.elapsed(at: context.date)
            HStack(spacing: 8) {
                time(PlaybackState.positionLabel(position), alignment: .trailing)
                if duration > 0 {
                    bar(fraction: position / duration, duration: duration)
                    time("-" + PlaybackState.positionLabel(duration - position), alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .accessibilityRepresentation {
                // A slider, so VoiceOver reads it as one and its adjust gestures seek.
                if duration > 0 {
                    Slider(value: Binding(get: { position }, set: { seek($0) }), in: 0...duration) { Text("Position") }
                        .accessibilityValue(Text("\(PlaybackState.positionLabel(position)) of \(PlaybackState.positionLabel(duration))"))
                } else {
                    Text(verbatim: PlaybackState.positionLabel(position))
                        .accessibilityLabel("Position")
                }
            }
        }
        // Taller than the bar, so it's an easy target.
        .frame(height: 24)
    }

    private func time(_ text: String, alignment: Alignment) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Native.secondary)
            .frame(minWidth: 34, alignment: alignment)
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(.white).frame(width: width * fraction)
                Circle().fill(.white)
                    .frame(width: 9, height: 9)
                    .offset(x: width * fraction - 4.5)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragged = min(max($0.location.x / width, 0), 1) }
                    .onEnded { value in
                        seek(min(max(value.location.x / width, 0), 1) * duration)
                        dragged = nil
                    }
            )
        }
    }
}

/// The output's volume between a quiet and a loud speaker, set as the pointer drags.
private struct VolumeSlider: View {
    let volume: Double
    let isMuted: Bool
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                .frame(width: 34, alignment: .trailing)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(.white).frame(width: width * volume)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { set(min(max($0.location.x / width, 0), 1)) }
                )
            }
            Image(systemName: "speaker.wave.3.fill")
                .frame(width: 34, alignment: .leading)
        }
        .font(.system(size: 10))
        .foregroundStyle(Native.secondary)
        .frame(height: 24)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { volume }, set: set), in: 0...1) { Text("Volume") }
        }
    }
}

/// Previous, play or pause, and next in the middle, with shuffle and repeat either side when the app reports them.
private struct PlaybackControls: View {
    let playback: PlaybackState
    let send: (PlaybackCommand) -> Void

    var body: some View {
        // Shuffle and repeat sit at the edges, over the middle three, so those stay centred whichever shows.
        ZStack {
            HStack(spacing: 12) {
                control("backward.fill", size: 16) { send(.previousTrack) }
                    .accessibilityLabel("Previous track")
                control(playback.isPlaying ? "pause.fill" : "play.fill", size: 22) { send(.togglePlayPause) }
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                control("forward.fill", size: 16) { send(.nextTrack) }
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

    /// A white symbol, or grey for a mode that's off, on a target at least 30 points square.
    private func control(_ symbol: String, size: CGFloat, on: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(Native.secondary))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
