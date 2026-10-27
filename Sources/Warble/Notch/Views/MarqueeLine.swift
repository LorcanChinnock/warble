import AppKit
import SwiftUI
import WarbleModel

/// One line of the expanded card's text. It fits, or ends in "…"; one that doesn't fit, while the song plays and Reduce
/// Motion is off, holds still for `TitleScroll.startDelay` and then scrolls in a loop (`ScrollingTitle`). The view lives
/// only while it scrolls, so pausing or closing the card brings back the plain text.
struct MarqueeLine: View {
    let text: String
    let font: NSFont
    /// Greyed, as the artist and album are; otherwise white, as the title is.
    var isSecondary = false
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment
    @State private var width: CGFloat = 0

    var body: some View {
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let height = ceil(font.ascender - font.descender)
        let scrolls = TitleScroll.scrolls(textWidth: textWidth, width: width, isPlaying: isPlaying, reduceMotion: reduceMotion)
        let color = isSecondary ? Native.secondary.resolve(in: environment) : Color.white
        Text(verbatim: text)
            .font(Font(font))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(scrolls ? 0 : 1)
            .overlay {
                if scrolls {
                    ScrollingTitle(title: text, font: font, width: width, height: height,
                                   color: NSColor(color), delay: TitleScroll.startDelay)
                        .frame(width: width, height: height)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width, initial: true) { width = $1 }
                }
            }
    }
}
