import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The output's volume after a speaker, set as the pointer drags. A click on the speaker mutes the output, or unmutes it
/// at the volume it had.
struct VolumeSlider: View {
    let volume: Double
    let isMuted: Bool
    let set: (Double) -> Void
    let toggleMute: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while the pointer is on the bar, when the fill follows it at once instead of easing.
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    // The wash reaches 6 pt past the symbol on each side, into the gap before the bar, so the symbol stays
                    // right-aligned in its column, under where a short elapsed time ends.
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(reduceMotion ? nil : Native.symbolSwap, value: isMuted)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .hoverWash(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.notch)
            .padding(.trailing, -6)
            .frame(width: 34, alignment: .trailing)
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Native.track)
                    Capsule().fill(.white).frame(width: width * volume)
                        .animation(isDragging || reduceMotion ? nil : Native.volumeEase, value: volume)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged {
                            isDragging = true
                            set(min(max($0.location.x / width, 0), 1))
                        }
                        .onEnded { _ in isDragging = false }
                )
            }
            .accessibilityRepresentation {
                Slider(value: Binding(get: { volume }, set: { set($0) }), in: 0...1) { Text("Volume") }
                    // VoiceOver reads this, not the slider's raw 0 to 1.
                    .accessibilityValue(isMuted ? Text("Muted") : Text("\(Int((volume * 100).rounded())) percent"))
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Native.secondary)
        .frame(height: 24)
    }
}
