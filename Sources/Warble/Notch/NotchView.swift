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
    /// The checks behind the "!", shared by every display's notch.
    let doctor: DoctorModel
    /// Whether the open card shows the Doctor's checks rather than the player.
    var showsDoctor = false
    /// What Expanded holds. `NotchSurface` sets it with `state`, inside the same animation, so a change of card morphs.
    var card = NotchCard.player
    /// Whether the notch shows what's playing, rather than Idle. While Idle, `player` may still hold the paused track.
    /// Set with `state`, like `card`.
    var isPlaying = false
    /// Whether the housing is one Warble draws on a display without a notch, where Idle shows nothing at all rather
    /// than black over the camera.
    var isVirtual = false
    /// Whether its display is set to show a notch always, so Idle draws a blank notch even on a virtual housing.
    var isAlwaysShown = false
    /// The track-change toast, while `state` is `toast`. Set with `state`, like `card`.
    var toast: TrackToast?
    @ObservationIgnored var onClick: () -> Void = {}
    /// Called with true when a menu from the card opens, and false when it closes, so the card stays open under it.
    @ObservationIgnored var onMenu: (Bool) -> Void = { _ in }
    /// Called to swap the open card between the player and the checks.
    @ObservationIgnored var onShowDoctor: (Bool) -> Void = { _ in }

    init(player: PlayerModel, doctor: DoctorModel) {
        self.player = player
        self.doctor = doctor
    }

    /// Hidden and Idle draw at the housing's size, black on black, so the wings slide out from behind it and back in.
    func size(_ state: NotchState) -> CGSize {
        NotchLayout.frame(state, notch: notch, card: card)?.size ?? notch.size
    }
}

/// What's playing and the controls for it, which every display's notch shows. The artwork is decoded and its colours
/// picked once, however many notches there are.
@MainActor
@Observable
final class PlayerModel {
    /// The last track played, which the idle card shows. It outlasts what's playing, and Warble too.
    var lastPlayed: LastPlayed? {
        didSet {
            if lastPlayed?.artwork != oldValue?.artwork {
                lastPlayedArtwork = lastPlayed?.artwork.flatMap(NSImage.init(data:))
            }
        }
    }
    private(set) var lastPlayedArtwork: NSImage?
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
                .id(ContentID(state: state == .toast ? .resting : state, card: model.card, isPlaying: playback != nil))
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
/// starting beside the "!", fades too. A toast is Resting's content with a strip below, so the wings stay put while
/// only the strip comes and goes.
private struct ContentID: Hashable {
    let state: NotchState
    let card: NotchCard
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
    let card: NotchCard
    let playback: PlaybackState?
    let artwork: NSImage?
    let colours: ArtworkColours?
    let model: NotchModel

    var body: some View {
        switch (state, card, playback) {
        case (.expanded, .player, let playback?):
            ExpandedContent(playback: playback, artwork: artwork, model: model)
                .padding(.top, model.notch.height)
                .background { Glow(colours: colours) }
        case (.expanded, .doctor, _):
            DoctorCard(model: model)
                .padding(.top, model.notch.height)
        case (.expanded, .idle, _):
            IdleCard(model: model)
                .padding(.top, model.notch.height)
        case (.resting, _, let playback?), (.toast, _, let playback?):
            VStack(spacing: 0) {
                RestingContent(playback: playback, artwork: artwork, notch: model.notch, model: model)
                if state == .toast, let toast = model.toast {
                    ToastLines(toast: toast)
                        // A skip while it shows swaps the words with a fade.
                        .id(toast)
                        .transition(ContentTransition())
                }
            }
        case (.resting, _, nil):
            RestingContent(playback: nil, artwork: nil, notch: model.notch, model: model)
        default:
            Color.clear.accessibilityHidden(true)
        }
    }
}

/// While Idle: the last track played, its art dimmed, with a button that resumes it, or a line saying nothing has
/// played yet.
private struct IdleCard: View {
    let model: NotchModel

    var body: some View {
        Group {
            if let lastPlayed = model.player.lastPlayed {
                HStack(spacing: 12) {
                    Button(action: model.player.onOpenApp) {
                        Artwork(image: model.player.lastPlayedArtwork, symbolSize: 20)
                            .frame(width: 48, height: 48)
                            .opacity(Native.dimmed)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lastPlayed.appName.map { Text("Open \($0)") } ?? Text("Open the app that played it"))
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if let appName = lastPlayed.appName { Text("Last played · \(appName)") } else { Text("Last played") }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Native.secondary)
                        Text(lastPlayed.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if let artist = lastPlayed.artist {
                            Text(artist)
                                .font(.system(size: 13))
                                .foregroundStyle(Native.secondary)
                        }
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button { model.player.onCommand(.togglePlayPause) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume")
                }
            } else {
                VStack(spacing: 3) {
                    Text("Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Play something and it shows here")
                        .font(.system(size: 12))
                        .foregroundStyle(Native.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

/// A track-change toast: the new title, and the artist under it, in the strip below the resting wings.
private struct ToastLines: View {
    let toast: TrackToast

    var body: some View {
        VStack(spacing: 1) {
            Text(toast.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if let artist = toast.artist {
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Native.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: NotchLayout.toastDrop)
        .accessibilityElement(children: .combine)
    }
}

/// The art in the left wing and the play-state bars in the right, either side of the camera housing, each centred in a
/// square as tall as the housing. When a Doctor check fails, a "!" takes the bars' place, and with nothing playing it's
/// all that shows.
private struct RestingContent: View {
    let playback: PlaybackState?
    let artwork: NSImage?
    let notch: CGRect
    let model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set once the wings appear, so the art grows and the bars rise as they slide out.
    @State private var appeared = false

    var body: some View {
        let wing = NotchLayout.wing(notch: notch)
        let art = wing - 2 * NotchLayout.inset(notch: notch)
        // Content on its way out still reads the model, so the bars drop as the notch leaves Resting. A toast keeps them.
        let isIn = appeared && (model.state == .resting || model.state == .toast)
        HStack(spacing: 0) {
            Group {
                if let playback {
                    Artwork(image: artwork, radius: art / 4, symbolSize: art / 2)
                        .frame(width: art, height: art)
                        // Grows into place as the wings slide out. With Reduce Motion it only fades.
                        .scaleEffect(isIn || reduceMotion ? 1 : NotchMotion.artScale)
                        .animation(isIn ? Native.artIn : Native.contentOut, value: isIn)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(playback.artist.map { Text("\(playback.title) by \($0)") } ?? Text(playback.title))
                        .accessibilityValue(playback.isPlaying ? Text("Playing") : Text("Paused"))
                }
            }
            .frame(width: wing)
            Spacer(minLength: 0)
            Group {
                if model.doctor.needsAttention {
                    AttentionButton(model: model, size: art)
                } else if let playback {
                    PlayStateBars(isPlaying: playback.isPlaying, isShown: isIn, reduceMotion: reduceMotion)
                        .frame(width: min(18, art), height: art * 0.6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: wing)
        }
        .frame(height: notch.height)
        .onAppear { appeared = true }
    }
}

/// The "!" that opens the notch on the Doctor's checks, in a square `size` points wide.
private struct AttentionButton: View {
    let model: NotchModel
    let size: CGFloat

    var body: some View {
        Button {
            model.onShowDoctor(true)
            model.onClick()
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size / 2))
                .foregroundStyle(Native.secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show what's wrong")
        .help("Warble can't see everything")
    }
}

/// Four bars that rise and fall while something plays and settle when it pauses. They follow the play state, not the
/// audio. Core Animation runs them in the window server, so the app does no work per frame. They rise one after another
/// as the wings slide out, and drop as the content leaves; once the content is gone, so are their animations. With
/// Reduce Motion they stand still and show at once.
private struct PlayStateBars: NSViewRepresentable {
    let isPlaying: Bool
    /// Whether the content around them is in, rather than coming or going.
    let isShown: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> BarsView {
        BarsView()
    }

    func updateNSView(_ view: BarsView, context: Context) {
        view.show(isPlaying ? (reduceMotion ? .still : .moving) : .settled, shown: isShown, animated: !reduceMotion)
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
        /// The curve each bar rises on, the same as the resting art's (`Native.artIn`).
        private static let rise = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        private let bars = heights.map { _ in CALayer() }
        private var look = Look.settled
        private var shown = false
        /// Whether the bars have been drawn yet. They're drawn hidden first, so they rise once they're shown.
        private var drawn = false
        /// When the bars started to rise, while they may still be rising, so a layout mid-rise carries on from there.
        private var riseBegan: CFTimeInterval?

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
            animate()
        }

        /// Shows `look`, with the bars up when `shown` and gone when not. `animated` staggers their rise and eases their
        /// drop; a change of look always eases.
        func show(_ look: Look, shown: Bool, animated: Bool) {
            defer { drawn = true }
            guard look != self.look || shown != self.shown else { return }
            let animated = animated && drawn
            let rises = shown && !self.shown
            let drops = !shown && self.shown
            self.look = look
            self.shown = shown
            riseBegan = rises && animated ? CACurrentMediaTime() : nil
            // Hold each bar where it is before its animations go, so it moves on from there rather than jumping.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars {
                if let height = bar.presentation()?.bounds.height { bar.bounds.size.height = height }
                bar.removeAllAnimations()
            }
            CATransaction.commit()
            CATransaction.begin()
            if rises || (drops && !animated) {
                // A rise is animate()'s; it starts from nothing.
                CATransaction.setDisableActions(true)
            } else if drops {
                CATransaction.setAnimationDuration(NotchMotion.barDrop)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
            } else {
                CATransaction.setAnimationDuration(0.25)
            }
            for (index, bar) in bars.enumerated() {
                bar.bounds.size.height = height(of: index)
            }
            CATransaction.commit()
            animate()
        }

        private func height(of index: Int) -> CGFloat {
            guard shown else { return 0 }
            return switch look {
            case .settled, .moving: Self.settled
            case .still: Self.heights[index][0] * bounds.height
            }
        }

        /// Adds each bar's rise while it's due or under way, then, while playing, its loop from where the rise ends.
        private func animate() {
            guard shown, bounds.height > 0 else { return }
            let now = CACurrentMediaTime()
            if let riseBegan, riseBegan + NotchMotion.barsRisen(count: bars.count) <= now {
                self.riseBegan = nil
            }
            for (index, bar) in bars.enumerated() {
                let loop = Self.heights[index].map { max($0 * bounds.height, Self.settled) }
                var loopBegins: CFTimeInterval = 0
                if let riseBegan {
                    let begins = riseBegan + NotchMotion.barDelay(index)
                    let rise = CABasicAnimation(keyPath: "bounds.size.height")
                    rise.fromValue = 0
                    rise.toValue = look == .moving ? loop[0] : height(of: index)
                    rise.beginTime = begins
                    rise.duration = NotchMotion.barRise
                    rise.timingFunction = Self.rise
                    // Nothing before its turn, and its top after, until the loop takes over.
                    rise.fillMode = .both
                    rise.isRemovedOnCompletion = false
                    bar.add(rise, forKey: "rise")
                    loopBegins = begins + NotchMotion.barRise
                } else {
                    bar.removeAnimation(forKey: "rise")
                }
                guard look == .moving else { continue }
                let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
                animation.values = loop + [loop[0]]
                animation.calculationMode = .cubic
                animation.beginTime = loopBegins
                // Slow enough that 8 frames a second reads as motion rather than steps. Each frame costs the window
                // server a redraw of the notch: about 1.7% of a core at 8, against about 21% at the display's rate.
                animation.duration = Double(loop.count) * 0.35
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
    let artwork: NSImage?
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.player.onOpenApp) {
                    Artwork(image: artwork)
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
                if model.doctor.needsAttention {
                    Button { model.onShowDoctor(true) } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Native.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show what's wrong")
                }
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
                UnevenRoundedRectangle(bottomLeadingRadius: Native.expandedRadius, bottomTrailingRadius: Native.expandedRadius)
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
