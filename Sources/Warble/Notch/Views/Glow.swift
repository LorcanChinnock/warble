import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The artwork's two colours rising from the card's bottom corners, or with Increase Contrast a solid border in the
/// first. Both stop short of the top edge, which stays black to merge with the housing. While a song plays the pools drift
/// (`DriftGlow`); paused, or with Reduce Motion on, they stand still, so a card left open then costs the window server
/// nothing.
struct Glow: View {
    let colours: ArtworkColours?
    let isPlaying: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let colours {
            if contrast == .increased {
                UnevenRoundedRectangle(bottomLeadingRadius: Native.expandedRadius, bottomTrailingRadius: Native.expandedRadius)
                    .strokeBorder(Color(colours.border), lineWidth: Native.contrastBorder)
                    // Leaves out the top edge, along the screen's.
                    .mask { Rectangle().padding(.top, Native.contrastBorder) }
            } else if !reduceMotion {
                DriftGlow(colours: colours, isPlaying: isPlaying)
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

private extension Color {
    init(_ colour: ArtworkColours.RGB) {
        self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue)
    }
}
