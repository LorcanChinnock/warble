import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The output's volume after a speaker, set as the pointer drags.
struct VolumeSlider: View {
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
        }
        .font(.system(size: 10))
        .foregroundStyle(Native.secondary)
        .frame(height: 24)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { volume }, set: set), in: 0...1) { Text("Volume") }
        }
    }
}
