import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The artwork's two colours rising from the card's bottom corners, or with Increase Contrast a solid border in the
/// first. With `showsGlow` off the card stays plain black, but the border stays. Both stop short of the top edge, which stays black to merge with the housing. It never animates on its own,
/// so a card left open costs the window server nothing.
struct Glow: View {
    let colours: ArtworkColours?
    var showsGlow = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let colours {
            if contrast == .increased {
                UnevenRoundedRectangle(bottomLeadingRadius: Native.expandedRadius, bottomTrailingRadius: Native.expandedRadius)
                    .strokeBorder(Color(colours.border), lineWidth: Native.contrastBorder)
                    // Leaves out the top edge, along the screen's.
                    .mask { Rectangle().padding(.top, Native.contrastBorder) }
            } else if showsGlow {
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
