import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore
import WarbleModel

/// The elapsed and remaining time either side of a bar that seeks where it's released. While dragging, the bar and the
/// time follow the pointer and nothing is sent; a live stream, which has no end, shows only the elapsed time. While the
/// pointer is over the bar, a label above it shows the time there, or while dragging the time the drag will seek to.
struct Scrubber: View {
    let playback: PlaybackState
    let seek: (TimeInterval) -> Void
    /// The position the pointer is dragging to, as a fraction of the track.
    @State private var dragged: Double?
    /// Where the pointer is along the bar while it's over it, which grows the knob and places the time label. The
    /// card is only in the view while open, so nothing tracks the pointer once it closes.
    @State private var pointer: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// A time in a fixed 34 pt column, the width of the speaker icon and output button below, so the bar's ends line up
    /// with the volume bar's. A longer time, such as -12:34 or 1:02:03, runs outward into the card's margin rather than
    /// pushing the bar in.
    private func time(_ text: String, alignment: Alignment) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Native.secondary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: 34, alignment: alignment)
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max(fraction, 0), 1)
            // The filled part ends in its own rounded tip, and grows a knob to drag while the pointer is on the bar.
            let grown = pointer != nil || dragged != nil
            // While dragging, the label shows where the drag will seek to; otherwise the time under the pointer.
            let labelX = dragged.map { $0 * width } ?? pointer
            let label = labelX.flatMap { ScrubberHandle.timeLabel(atX: $0, width: width, duration: duration) }
            ZStack {
                Capsule().fill(Native.track).frame(height: ScrubberHandle.barHeight)
                BarFill(fraction: fraction, grown: grown ? 1 : 0)
                    .fill(.white)
                    .animation(reduceMotion ? nil : .smooth(duration: ScrubberHandle.growDuration), value: grown)
            }
            .overlay(alignment: .topLeading) {
                ZStack {
                    if let label, let labelX {
                        timeLabel(label)
                            .position(x: min(max(labelX, 0), width), y: geometry.size.height / 2 - 17)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: ScrubberHandle.growDuration), value: label != nil)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer = location.x
                case .ended: pointer = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragged = ScrubberHandle.fraction(atX: $0.location.x, width: width) }
                    .onEnded { value in
                        seek(ScrubberHandle.fraction(atX: value.location.x, width: width) * duration)
                        dragged = nil
                    }
            )
        }
    }

    /// The time at the pointer, in white on a black pill so it reads over the card's text and glow. VoiceOver skips it:
    /// the bar already reads as a slider with its position.
    private func timeLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Native.panel))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The filled part of the bar and its knob as one outline, so there's no seam or dip where they meet.
private struct BarFill: Shape {
    let fraction: Double
    var grown: Double

    var animatableData: Double {
        get { grown }
        set { grown = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let handle = ScrubberHandle(fraction: fraction, width: rect.width, grown: grown)
        let half = ScrubberHandle.barHeight / 2
        let mid = rect.midY
        let at = { (p: CGPoint, flip: CGFloat) in CGPoint(x: rect.minX + p.x, y: mid + p.y * flip) }
        let bar = Path(
            roundedRect: CGRect(x: rect.minX, y: mid - half, width: handle.centre, height: 2 * half),
            cornerRadius: half
        )
        let r = handle.radius
        var outline = bar.union(Path(ellipseIn: CGRect(x: rect.minX + handle.centre - r, y: mid - r, width: 2 * r, height: 2 * r)))
        if let fillet = handle.fillet {
            // Fill the corner above and below the join, from the bar's edge along the curve to the knob.
            for flip: CGFloat in [1, -1] {
                var corner = Path()
                corner.move(to: at(fillet.start, flip))
                corner.addCurve(to: at(fillet.end, flip), control1: at(fillet.control1, flip), control2: at(fillet.control2, flip))
                corner.addLine(to: CGPoint(x: rect.minX + handle.centre, y: mid))
                corner.addLine(to: CGPoint(x: rect.minX + fillet.start.x, y: mid))
                corner.closeSubpath()
                outline = outline.union(corner)
            }
        }
        return outline
    }
}
