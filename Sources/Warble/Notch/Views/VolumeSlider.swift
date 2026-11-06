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

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    // The wash reaches 6 pt past the symbol on each side, into the gap before the bar, so the symbol stays
                    // right-aligned in its column, under where a short elapsed time ends.
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
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { set(min(max($0.location.x / width, 0), 1)) }
                )
            }
            .accessibilityRepresentation {
                Slider(value: Binding(get: { volume }, set: { set($0) }), in: 0...1) { Text("Volume") }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Native.secondary)
        .frame(height: 24)
    }
}
