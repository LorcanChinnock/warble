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
                // Artwork that isn't square, such as a video's thumbnail, is fitted whole rather than cropped, and the
                // tile shrinks to the picture, so there are no bars. The caller's frame centres it.
                Image(nsImage: image).resizable().scaledToFit()
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
