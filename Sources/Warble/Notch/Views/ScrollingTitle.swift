import AppKit
import SwiftUI
import WarbleModel

/// A line too long for its room, moving slowly from right to left in a loop with both edges faded. Core Animation runs
/// the loop in the window server, so the app does no work per frame, at a low frame rate since each frame redraws the
/// notch. It exists only while the song plays: when the view goes, so does the animation.
struct ScrollingTitle: NSViewRepresentable {
    let title: String
    let font: NSFont
    /// The room the title scrolls through.
    let width: CGFloat
    let height: CGFloat
    var color: NSColor = .white
    /// How long it holds still, with its start in full, before the loop begins; Core Animation waits, so nothing is
    /// scheduled here.
    var delay: TimeInterval = 0

    func makeNSView(context: Context) -> ScrollView {
        ScrollView()
    }

    func updateNSView(_ view: ScrollView, context: Context) {
        view.show(title, font: font, color: color, width: width, height: height, delay: delay)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ScrollView, context: Context) -> CGSize? {
        CGSize(width: width, height: height)
    }

    final class ScrollView: NSView {
        /// The length of the fade at each edge.
        private static let fade: CGFloat = 14
        /// Slow enough to need few frames, fast enough that 18 points a second doesn't step.
        private static let frameRate = CAFrameRateRange(minimum: 15, maximum: 20, preferred: 20)
        /// Two copies of the title a loop apart, which moves left by that distance and starts over.
        private let strip = CALayer()
        private let first = CATextLayer()
        private let second = CATextLayer()
        private let edges = CAGradientLayer()
        private var shown: (title: String, font: NSFont, color: NSColor, width: CGFloat, height: CGFloat, delay: TimeInterval)?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            layer?.addSublayer(strip)
            for text in [first, second] {
                text.alignmentMode = .left
                text.truncationMode = .none
                strip.addSublayer(text)
            }
            edges.startPoint = CGPoint(x: 0, y: 0.5)
            edges.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.mask = edges
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(_ title: String, font: NSFont, color: NSColor, width: CGFloat, height: CGFloat, delay: TimeInterval) {
            if let shown, shown.title == title, shown.font == font, shown.color == color, shown.width == width, shown.height == height,
               shown.delay == delay { return }
            shown = (title, font, color, width, height, delay)
            let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
            let distance = TitleScroll.distance(textWidth: textWidth)
            let textHeight = ceil(font.ascender - font.descender)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            strip.removeAllAnimations()
            edges.removeAllAnimations()
            strip.frame = CGRect(x: 0, y: 0, width: distance + textWidth, height: height)
            for (index, text) in [first, second].enumerated() {
                text.string = title
                text.foregroundColor = color.cgColor
                text.font = font
                text.fontSize = font.pointSize
                text.frame = CGRect(x: CGFloat(index) * distance, y: (height - textHeight) / 2, width: textWidth, height: textHeight)
            }
            edges.frame = CGRect(x: 0, y: 0, width: width, height: height)
            let ratio = min(0.5, Self.fade / max(width, 1))
            let faded = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            edges.colors = faded
            edges.locations = [0, ratio, 1 - ratio, 1].map(NSNumber.init(value:))
            CATransaction.commit()
            let loop = CABasicAnimation(keyPath: "transform.translation.x")
            loop.fromValue = 0
            loop.toValue = -distance
            loop.duration = TitleScroll.duration(textWidth: textWidth)
            loop.repeatCount = .infinity
            loop.timingFunction = CAMediaTimingFunction(name: .linear)
            loop.preferredFrameRateRange = Self.frameRate
            if delay > 0 {
                // Until it starts the line sits at its start, which has no fade at its left edge.
                loop.beginTime = strip.convertTime(CACurrentMediaTime(), from: nil) + delay
                loop.fillMode = .backwards
                let reveal = CABasicAnimation(keyPath: "colors")
                reveal.fromValue = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
                reveal.toValue = faded
                reveal.beginTime = loop.beginTime
                reveal.duration = 0.3
                reveal.fillMode = .backwards
                edges.add(reveal, forKey: "reveal")
            }
            strip.add(loop, forKey: "scroll")
            matchScreen()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            matchScreen()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            matchScreen()
        }

        /// Draws the text at the density of the screen it's on, which is only known once it's in a window and changes if
        /// the window moves to another display; layers added by hand don't follow it themselves.
        private func matchScreen() {
            guard let scale = window?.backingScaleFactor else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            first.contentsScale = scale
            second.contentsScale = scale
            CATransaction.commit()
        }
    }
}
