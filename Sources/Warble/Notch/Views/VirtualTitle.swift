import AppKit
import SwiftUI
import WarbleCore
import WarbleModel

/// What's playing, in the middle of a resting virtual notch, where a real one has the camera. It stays as wide as the
/// notch. A title that doesn't fit scrolls slowly in a loop while the song plays (`ScrollingTitle`, in Core Animation);
/// paused, or with Reduce Motion, it has its end faded and stays where it is. The full title is in the player. Nothing
/// waits on a timer.
struct VirtualTitle: View {
    let playback: PlaybackState
    let notch: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room kept clear of the notch's edges, and the length of the fade at the right one.
    private static let margin: CGFloat = 8
    private static let fade: CGFloat = 14

    var body: some View {
        let font = NSFont.systemFont(ofSize: min(13, max(11, notch.height * 0.46)), weight: .medium)
        let width = notch.width - 2 * Self.margin
        let line = TrackTitle.line(title: playback.title, artist: playback.artist, width: width) {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }
        if case .faded(let title) = line, TitleScroll.scrolls(line, isPlaying: playback.isPlaying, reduceMotion: reduceMotion) {
            ScrollingTitle(title: title, font: font, width: width, height: notch.height)
                .padding(.horizontal, Self.margin)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            still(line, font: font, width: width)
        }
    }

    private func still(_ line: TrackTitle.Line, font: NSFont, width: CGFloat) -> some View {
        let titleStyle = playback.isPlaying ? AnyShapeStyle(Color.white) : AnyShapeStyle(Native.secondary)
        return Group {
            switch line {
            case .titleAndArtist(let title, let artist):
                Text(verbatim: title).foregroundStyle(titleStyle) + Text(verbatim: "  ") + Text(verbatim: artist).foregroundStyle(Native.secondary)
            case .title(let title), .faded(let title):
                Text(verbatim: title).foregroundStyle(titleStyle)
            }
        }
        .font(Font(font))
        .lineLimit(1)
        .fixedSize()
        .frame(width: width, alignment: line.isCut ? .leading : .center)
        .mask(alignment: .leading) { fadeMask(fades: line.isCut, width: width) }
        .frame(height: notch.height)
        // Back out to the notch's width, so the wings stay where they are without a title.
        .padding(.horizontal, Self.margin)
        .allowsHitTesting(false)
        // The art already reads "Now playing: <title> by <artist>".
        .accessibilityHidden(true)
    }

    private func fadeMask(fades: Bool, width: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: fades ? max(0, 1 - Self.fade / max(width, 1)) : 1),
                .init(color: fades ? .clear : .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: width)
    }
}
