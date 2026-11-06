import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore
import WarbleModel

/// The elapsed and remaining time either side of a bar that seeks where it's released. While dragging, the bar and the
/// time follow the pointer and nothing is sent; a live stream, which has no end, shows only the elapsed time.
struct Scrubber: View {
    let playback: PlaybackState
    let seek: (TimeInterval) -> Void
    /// The position the pointer is dragging to, as a fraction of the track.
    @State private var dragged: Double?
    /// Whether the pointer is over the bar, which grows the knob.
    @State private var hovering = false
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
            // The filled part ends in its own rounded tip, and grows a knob to drag while the pointer is on the bar.
            let grown = hovering || dragged != nil
            ZStack {
                Capsule().fill(Native.track).frame(height: ScrubberHandle.barHeight)
                BarFill(fraction: fraction, grown: grown ? 1 : 0)
                    .fill(.white)
                    .animation(reduceMotion ? nil : .smooth(duration: ScrubberHandle.growDuration), value: grown)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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
