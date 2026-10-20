#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The three bars of Warble's mark: a medium one, a tall one, then a short one, each with fully rounded ends. The app
/// icon (`make icon` builds `scripts/make-icon.swift` with this file) and the menu bar icon both draw them from here.
public enum IconBars {
    /// The bars on the app icon's 1024-point canvas, bottom-left origin, left to right.
    public static let rects: [CGRect] = {
        let width: CGFloat = 96, gap: CGFloat = 56, baseline: CGFloat = 250
        return [CGFloat(250), 380, 190].enumerated().map { index, height in
            CGRect(x: 512 - (width * 1.5 + gap) + CGFloat(index) * (width + gap), y: baseline, width: width, height: height)
        }
    }()

    /// The bar the app icon fills with its accent colour.
    public static let accent = 1

    /// The bars scaled so the tallest is `height` points, from the origin. Their sides fall on whole points so a
    /// small icon stays sharp, which can nudge the gaps from the app icon's proportions by a fraction of a point.
    public static func rects(height: CGFloat) -> [CGRect] {
        let scale = height / rects.map(\.height).max()!
        let width = max((rects[0].width * scale).rounded(), 1)
        let gap = max(((rects[1].minX - rects[0].maxX) * scale).rounded(), 1)
        return rects.enumerated().map { index, bar in
            CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bar.height * scale)
        }
    }
}
