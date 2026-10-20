import AppKit
import SwiftUI
import WarbleCore

/// What one notch panel draws. `NotchController` changes `state` inside an animation, and the view morphs to it.
@MainActor
@Observable
final class NotchModel {
    var state = NotchState.hidden
    /// The camera housing, real or virtual, which every state's shape is measured from.
    var notch = CGRect.zero
    /// What's playing, shared by every display's notch.
    let player: PlayerModel
    @ObservationIgnored var onClick: () -> Void = {}
    /// Called with true when a menu from the card opens, and false when it closes, so the card stays open under it.
    @ObservationIgnored var onMenu: (Bool) -> Void = { _ in }

    init(player: PlayerModel) {
        self.player = player
    }

    /// Hidden draws at the housing's size, black on black, so the wings slide out from behind it and back in.
    func size(_ state: NotchState) -> CGSize {
        NotchLayout.frame(state, notch: notch)?.size ?? notch.size
    }
}

/// What's playing and the controls for it, which every display's notch shows. The artwork is decoded and its colours
/// picked once, however many notches there are.
@MainActor
@Observable
final class PlayerModel {
    var playback: PlaybackState? {
        didSet {
            let artworkChanged = playback?.artwork != oldValue?.artwork
            let appChanged = playback?.bundleIdentifier != oldValue?.bundleIdentifier
            if artworkChanged {
                artwork = playback?.artwork.flatMap(NSImage.init(data:))
            }
            if appChanged {
                appName = playback.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).first?.localizedName }
            }
            if artworkChanged || (appChanged && playback?.artwork == nil) {
                pickColours()
            }
        }
    }
    private(set) var artwork: NSImage?
    /// The glow's colours, from the artwork or, without it, the app's icon.
    private(set) var colours: ArtworkColours?
    /// Bumped by every pick, so a pick that finishes after the track has changed again is dropped.
    @ObservationIgnored private var colourPicks = 0
    /// The name of the app that's playing, for VoiceOver.
    private(set) var appName: String?
    @ObservationIgnored var onCommand: (PlaybackCommand) -> Void = { _ in }
    /// Brings the app that's playing to the front.
    @ObservationIgnored var onOpenApp: () -> Void = {}
    /// The output's volume from 0 to 1, read while Expanded shows; `nil` when it can't be changed.
    var volume: Double?
    var isMuted = false
    @ObservationIgnored var onVolume: (Double) -> Void = { _ in }
    /// The outputs to offer and the one playing, read while Expanded shows.
    var outputs: [AudioOutput] = []
    var currentOutput: UInt32?
    @ObservationIgnored var onSelectOutput: (UInt32) -> Void = { _ in }

    /// Picks the colours off the main thread, then fades the glow to them.
    private func pickColours() {
        colourPicks += 1
        let pick = colourPicks
        guard let playback else {
            colours = nil
            return
        }
        let artwork = playback.artwork
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: playback.bundleIdentifier)
        Task { [weak self] in
            let colours = await Task.detached(priority: .utility) { () -> ArtworkColours? in
                if let artwork {
                    return ArtworkColours(data: artwork)
                }
                var rect = CGRect(x: 0, y: 0, width: 32, height: 32)
                guard let app, let icon = NSWorkspace.shared.icon(forFile: app.path).cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
                return ArtworkColours(image: icon)
            }.value
            guard let self, pick == self.colourPicks, colours != self.colours else { return }
            withAnimation(Native.glowChange) { self.colours = colours }
        }
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
        switch (state, model.player.playback) {
        case (.expanded, let playback?):
            ExpandedContent(playback: playback, model: model)
                .padding(.top, model.notch.height)
                .background { Glow(colours: model.player.colours) }
        case (.resting, let playback?):
            RestingContent(playback: playback, artwork: model.player.artwork, height: model.notch.height)
        default:
            Color.clear.accessibilityHidden(true)
        }
    }
}

/// The art in the left wing and the play-state bars in the right, either side of the camera housing.
private struct RestingContent: View {
    let playback: PlaybackState
    let artwork: NSImage?
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = height - 2 * Native.restingInset
        HStack(spacing: 0) {
            Artwork(image: artwork, radius: 6, symbolSize: 12)
                .frame(width: art, height: art)
                .frame(width: NotchLayout.wing)
            Spacer(minLength: 0)
            PlayStateBars(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
                .frame(width: 18, height: art * 0.6)
                .frame(width: NotchLayout.wing)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playback.artist.map { Text("\(playback.title) by \($0)") } ?? Text(playback.title))
        .accessibilityValue(playback.isPlaying ? Text("Playing") : Text("Paused"))
    }
}

/// Four bars that rise and fall while something plays and settle when it pauses. They follow the play state, not the
/// audio. Core Animation runs them in the window server, so the app does no work per frame; with Reduce Motion they
/// stand still.
private struct PlayStateBars: NSViewRepresentable {
    let isPlaying: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> BarsView {
        BarsView()
    }

    func updateNSView(_ view: BarsView, context: Context) {
        view.show(isPlaying ? (reduceMotion ? .still : .moving) : .settled)
    }

    final class BarsView: NSView {
        enum Look { case settled, still, moving }

        /// Each bar's heights, as fractions of the view's, which it loops through. Different lengths keep the bars from
        /// falling into step.
        private static let heights: [[CGFloat]] = [
            [0.35, 0.9, 0.5, 1, 0.4],
            [0.8, 0.3, 1, 0.45],
            [0.5, 1, 0.3, 0.75, 0.6, 0.95],
            [0.9, 0.4, 0.7, 0.3],
        ]
        /// A paused bar, a rounded dot.
        private static let settled: CGFloat = 3
        private static let barWidth: CGFloat = 3
        private let bars = heights.map { _ in CALayer() }
        private var look = Look.settled

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            for bar in bars {
                bar.backgroundColor = NSColor.white.cgColor
                bar.cornerRadius = Self.barWidth / 2
                // Grows up from its foot.
                bar.anchorPoint = CGPoint(x: 0.5, y: 0)
                layer?.addSublayer(bar)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gap = (bounds.width - CGFloat(bars.count) * Self.barWidth) / CGFloat(bars.count - 1)
            for (index, bar) in bars.enumerated() {
                bar.position = CGPoint(x: CGFloat(index) * (Self.barWidth + gap) + Self.barWidth / 2, y: 0)
                bar.bounds.size = CGSize(width: Self.barWidth, height: height(of: index))
            }
            CATransaction.commit()
            if look == .moving {
                startMoving()
            }
        }

        func show(_ look: Look) {
            guard look != self.look else { return }
            let wasMoving = self.look == .moving
            self.look = look
            CATransaction.begin()
            if wasMoving {
                // Hold each bar where it is before the animation goes, so it settles from there rather than jumping.
                CATransaction.setDisableActions(true)
                for bar in bars {
                    if let height = bar.presentation()?.bounds.height { bar.bounds.size.height = height }
                    bar.removeAnimation(forKey: "height")
                }
                CATransaction.commit()
                CATransaction.begin()
            }
            CATransaction.setAnimationDuration(0.25)
            for (index, bar) in bars.enumerated() {
                bar.bounds.size.height = height(of: index)
            }
            CATransaction.commit()
            if look == .moving {
                startMoving()
            }
        }

        private func height(of index: Int) -> CGFloat {
            switch look {
            case .settled, .moving: Self.settled
            case .still: Self.heights[index][0] * bounds.height
            }
        }

        private func startMoving() {
            guard bounds.height > 0 else { return }
            for (index, bar) in bars.enumerated() {
                let values = Self.heights[index].map { max($0 * bounds.height, Self.settled) }
                let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
                animation.values = values + [values[0]]
                animation.calculationMode = .cubic
                // Slow enough that 8 frames a second reads as motion rather than steps. Each frame costs the window
                // server a redraw of the notch: about 1.7% of a core at 8, against about 21% at the display's rate.
                animation.duration = Double(values.count) * 0.35
                animation.repeatCount = .infinity
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 6, maximum: 8, preferred: 8)
                bar.add(animation, forKey: "height")
            }
        }
    }
}

/// The full card: art, title, artist and album, then the position and the controls.
private struct ExpandedContent: View {
    let playback: PlaybackState
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.player.onOpenApp) {
                    Artwork(image: model.player.artwork)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.player.appName.map { Text("Open \($0)") } ?? Text("Open the app that's playing"))
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
            Scrubber(playback: playback) { model.player.onCommand(.seek(to: $0)) }
            Spacer(minLength: 0)
            PlaybackControls(playback: playback, send: model.player.onCommand)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let volume = model.player.volume {
                    VolumeSlider(volume: model.player.isMuted ? 0 : volume, isMuted: model.player.isMuted, set: model.player.onVolume)
                } else {
                    Spacer(minLength: 0)
                }
                OutputButton(model: model)
                    .frame(width: 34, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// The artwork's two colours rising from the card's bottom corners, or with Increase Contrast a solid border in the
/// first. Both stop short of the top edge, which stays black to merge with the housing. It never animates on its own,
/// so a card left open costs the window server nothing.
private struct Glow: View {
    let colours: ArtworkColours?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let colours {
            if contrast == .increased {
                UnevenRoundedRectangle(bottomLeadingRadius: Native.radius(.expanded), bottomTrailingRadius: Native.radius(.expanded))
                    .strokeBorder(Color(colours.border), lineWidth: Native.contrastBorder)
                    // Leaves out the top edge, along the screen's.
                    .mask { Rectangle().padding(.top, Native.contrastBorder) }
            } else {
                ZStack {
                    corner(colours.first, at: .bottomLeading)
                    corner(colours.second, at: .bottomTrailing)
                }
            }
        }
    }

    private func corner(_ colour: ArtworkColours.RGB, at center: UnitPoint) -> some View {
        EllipticalGradient(colors: [Color(colour).opacity(Native.glowOpacity), .clear], center: center, endRadiusFraction: Native.glowReach)
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

/// The output's volume after a speaker, set as the pointer drags.
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
        }
        .font(.system(size: 10))
        .foregroundStyle(Native.secondary)
        .frame(height: 24)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { volume }, set: set), in: 0...1) { Text("Volume") }
        }
    }
}

/// The playing output's symbol, which opens a menu of the outputs with the playing one ticked. AirPlay receivers aren't
/// listed: they aren't Core Audio devices, and the system's route picker, the only public way to them, moves only
/// Warble's own audio.
private struct OutputButton: View {
    let model: NotchModel

    var body: some View {
        let playing = model.player.outputs.first { $0.id == model.player.currentOutput }
        ZStack {
            OutputMenu(model: model)
            Image(systemName: playing?.symbol ?? "hifispeaker")
                .font(.system(size: 12))
                .foregroundStyle(Native.secondary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct OutputMenu: NSViewRepresentable {
    let model: NotchModel

    func makeNSView(context: Context) -> OutputMenuView {
        OutputMenuView()
    }

    func updateNSView(_ view: OutputMenuView, context: Context) {
        view.outputs = model.player.outputs
        view.current = model.player.currentOutput
        view.select = model.player.onSelectOutput
        view.onMenu = model.onMenu
    }

    final class OutputMenuView: NSView {
        var outputs: [AudioOutput] = [] {
            didSet { setAccessibilityValue(playing?.name) }
        }
        var current: UInt32? {
            didSet { setAccessibilityValue(playing?.name) }
        }
        var select: (UInt32) -> Void = { _ in }
        var onMenu: (Bool) -> Void = { _ in }

        init() {
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.popUpButton)
            setAccessibilityLabel(String(localized: "Output"))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func mouseDown(with event: NSEvent) {
            showMenu()
        }

        override func accessibilityPerformPress() -> Bool {
            showMenu()
            return true
        }

        private var playing: AudioOutput? {
            outputs.first { $0.id == current }
        }

        private func showMenu() {
            let menu = NSMenu()
            for output in outputs {
                let item = NSMenuItem(title: output.name, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(output.id)
                item.image = NSImage(systemSymbolName: output.symbol, accessibilityDescription: nil)
                item.state = output.id == current ? .on : .off
                menu.addItem(item)
            }
            onMenu(true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY - 4), in: self)
            onMenu(false)
        }

        @objc private func choose(_ item: NSMenuItem) {
            select(UInt32(item.tag))
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

private extension Color {
    init(_ colour: ArtworkColours.RGB) {
        self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue)
    }
}

private struct Artwork: View {
    let image: NSImage?
    var radius: CGFloat = 8
    /// The placeholder note's size, when there's no art.
    var symbolSize: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let image {
                // Clear takes the size the caller gives, so artwork that isn't square, such as a video's, fills it and
                // is cropped rather than drawn at its own width.
                Color.clear.overlay {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else {
                shape.fill(Color(white: 0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: symbolSize))
                            .foregroundStyle(Native.secondary)
                    }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
