import AppKit
import SwiftUI
import WarbleCore

struct Artwork: View {
    let image: NSImage?
    var radius: CGFloat = 8
    /// The placeholder note's size, when there's no art.
    var symbolSize: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let image {
                // Clear takes the size the caller gives, so artwork that isn't square, such as a video's, fills it and
                // is cropped rather than drawn at its own width.
                Color.clear.overlay {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else {
                shape.fill(Color(white: 0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: symbolSize))
                            .foregroundStyle(Native.secondary)
                    }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
