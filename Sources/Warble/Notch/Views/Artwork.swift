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
                // The tile keeps the size the caller gives, and artwork that isn't square, such as a video's thumbnail,
                // is fitted inside it whole rather than cropped, with the placeholder's grey showing in the bars.
                Color(white: 0.15).overlay {
                    Image(nsImage: image).resizable().scaledToFit()
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
