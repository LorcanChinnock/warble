import AppKit
import SwiftUI
import WarbleCore

/// What's playing, in the middle of a resting virtual notch, where a real one has the camera. It stays as wide as the
/// notch. A title that doesn't fit has its end faded, and scrolls to its end once when the track changes, in Core
/// Animation, so the app does no work per frame and nothing loops. With Reduce Motion it never scrolls.
struct VirtualTitle: View {
    let playback: PlaybackState
    let notch: CGRect
    let model: NotchModel
    @Environment(\.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room kept clear of the notch's edges, and the length of the fade at the right one.
    private static let margin: CGFloat = 8
    private static let fade: CGFloat = 14
    private static let font = ScaledFont.scaled(13, weight: .medium)

    var body: some View {
        let font = NSFont.systemFont(ofSize: Self.font.points(textSize), weight: .medium)
        let width = notch.width - 2 * Self.margin
        let line = TrackTitle.line(title: playback.title, artist: playback.artist, width: width) {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }
        let textWidth = (line.text as NSString).size(withAttributes: [.font: font]).width
        // The end clears the fade, so the last letters show once it gets there.
        let travel = line.isCut ? textWidth - width + Self.fade : 0
        let key = line.text
        TitleLabel(
            text: line.text, font: font, fadesEnd: line.isCut, travel: travel,
            scrolls: !reduceMotion && line.isCut && model.scrolledTitle != key,
            fade: Self.fade, onScroll: { model.scrolledTitle = key }
        )
        .frame(width: width, height: notch.height)
        .allowsHitTesting(false)
        // The art already reads "Now playing: <title> by <artist>".
        .accessibilityHidden(true)
    }
}

private struct TitleLabel: NSViewRepresentable {
    let text: String
    let font: NSFont
    let fadesEnd: Bool
    /// How far the text moves to show its end.
    let travel: CGFloat
    /// Whether this title is due its one scroll.
    let scrolls: Bool
    let fade: CGFloat
    let onScroll: () -> Void

    func makeNSView(context: Context) -> LabelView {
        LabelView()
    }

    func updateNSView(_ view: LabelView, context: Context) {
        view.show(self)
    }

    final class LabelView: NSView {
        /// A text layer rather than a text field, which AppKit only draws the visible part of: the end of a long title
        /// would be missing as it scrolls into view.
        private let label = CATextLayer()
        private let fadeMask = CAGradientLayer()
        private var props: TitleLabel?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            label.foregroundColor = NSColor.white.cgColor
            label.alignmentMode = .left
            label.truncationMode = .none
            label.isWrapped = false
            layer?.addSublayer(label)
            fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
            fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
            // A mask rather than masksToBounds, so the end of the title is only cut at the notch's edges.
            layer?.mask = fadeMask
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            label.contentsScale = window?.backingScaleFactor ?? 2
        }

        override func layout() {
            super.layout()
            guard let props else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let size = (props.text as NSString).size(withAttributes: [.font: props.font])
            let height = ceil(size.height)
            // Centred when it fits, and from the left when it's cut.
            let x = props.fadesEnd ? 0 : (bounds.width - ceil(size.width)) / 2
            label.frame = CGRect(x: x, y: (bounds.height - height) / 2, width: ceil(size.width) + 1, height: height)
            fadeMask.frame = bounds
            fadeMask.locations = [NSNumber(value: max(0, 1 - props.fade / max(bounds.width, 1))), 1]
            CATransaction.commit()
        }

        func show(_ new: TitleLabel) {
            let changed = props?.text != new.text || props?.font != new.font
            props = new
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if changed {
                label.removeAnimation(forKey: "scroll")
                label.font = new.font
                label.fontSize = new.font.pointSize
                label.string = new.text
                label.contentsScale = window?.backingScaleFactor ?? 2
                needsLayout = true
            }
            fadeMask.colors = [NSColor.black.cgColor, new.fadesEnd ? NSColor.clear.cgColor : NSColor.black.cgColor]
            CATransaction.commit()
            if new.scrolls, label.animation(forKey: "scroll") == nil {
                scroll(by: new.travel)
                new.onScroll()
            }
        }

        private func scroll(by travel: CGFloat) {
            let (duration, keyTimes) = NotchMotion.titleScroll(travel: travel)
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, 0, -travel, -travel, 0]
            animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
            animation.calculationMode = .linear
            animation.duration = duration
            // Once. It ends where it began, so there's nothing to remove.
            animation.repeatCount = 1
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            label.add(animation, forKey: "scroll")
        }
    }
}
