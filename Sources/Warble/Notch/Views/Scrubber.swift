import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The elapsed and remaining time either side of a bar that seeks where it's released. While dragging, the bar and the
/// time follow the pointer and nothing is sent; a live stream, which has no end, shows only the elapsed time.
struct Scrubber: View {
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
            .font(.scaled(11, monospacedDigits: true))
            .foregroundStyle(Native.secondary)
            .frame(minWidth: 34, alignment: alignment)
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Native.track)
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
