import AppKit
import SwiftUI

/// The heart beside the title on the open card, while Music is playing and Settings has it on. A favourite is a filled
/// heart in the title's colour, and anything else an outline in grey, so the shape says which, not only the colour.
struct FavouriteButton: View {
    let isFavourite: Bool
    /// The title's colour, or white while there are no colours.
    let tint: NSColor?
    let toggle: () -> Void

    /// The side of the square the heart takes up, which the title leaves room for.
    static let size: CGFloat = 26

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFavourite ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFavourite ? AnyShapeStyle(tint.map(Color.init(nsColor:)) ?? .white) : AnyShapeStyle(Native.secondary))
                .frame(width: Self.size, height: Self.size)
                .hoverWash(Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.notch)
        .accessibilityLabel(isFavourite ? Text("Remove from Favourites") : Text("Add to Favourites"))
    }
}
