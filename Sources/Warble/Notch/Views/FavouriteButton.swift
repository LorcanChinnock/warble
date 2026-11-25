import AppKit
import SwiftUI
import WarbleModel

/// The heart beside the title on the open card, while Music is playing. A favourite is a filled
/// heart in the title's colour, and anything else an outline in grey, so the shape says which, not only the colour.
struct FavouriteButton: View {
    let isFavourite: Bool
    /// The title's colour, or white while there are no colours.
    let tint: NSColor?
    let toggle: () -> Void

    /// The side of the square the heart takes up, which the title leaves room for.
    static let size: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How big the heart is drawn: it swells when liked and settles back, and only settles when unliked.
    @State private var scale = 1.0

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFavourite ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFavourite ? AnyShapeStyle(tint.map(Color.init(nsColor:)) ?? .white) : AnyShapeStyle(Native.secondary))
                .scaleEffect(scale)
                .frame(width: Self.size, height: Self.size)
                .hoverWash(Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.notch)
        .onChange(of: isFavourite) { _, liked in
            guard !reduceMotion else { return }
            if liked {
                withAnimation(Native.heartPop) { scale = NotchMotion.heartPopScale } completion: {
                    withAnimation(Native.heartSettle) { scale = 1 }
                }
            } else {
                withAnimation(Native.heartSettle) { scale = 1 }
            }
        }
        .accessibilityLabel(isFavourite ? Text("Remove from Favourites") : Text("Add to Favourites"))
    }
}

extension View {
    /// The heart scaling and fading in when it first shows, or only fading with Reduce Motion. The caller animates the
    /// change that shows it with `Native.heartIn`.
    func favouriteAppears(reduceMotion: Bool) -> some View {
        transition(reduceMotion ? .opacity : .scale(scale: NotchMotion.heartAppearScale).combined(with: .opacity))
    }
}
