#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

/// What macOS reported for one scale in System Settings › Displays, on a display whose menu bar is at the top.
struct MeasuredScale: Sendable, CustomTestStringConvertible {
    /// The screen's size in points, which names the scale.
    var screen: CGSize
    var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea.maxX` and `auxiliaryTopRightArea.minX`.
    var leftAreaMaxX: CGFloat
    var rightAreaMinX: CGFloat
    /// The panel's own pixels across, the same at every scale.
    var panelPixels: CGFloat

    var testDescription: String { "\(Int(screen.width)) × \(Int(screen.height))" }

    /// Physical pixels to a point at this scale.
    var pixelsPerPoint: CGFloat { panelPixels / screen.width }

    var leftArea: CGRect {
        CGRect(x: 0, y: screen.height - safeAreaTop, width: leftAreaMaxX, height: safeAreaTop)
    }

    var rightArea: CGRect {
        CGRect(x: rightAreaMinX, y: screen.height - safeAreaTop, width: screen.width - rightAreaMinX, height: safeAreaTop)
    }
}

/// A 15-inch MacBook Air (M4, Mac16,13) at each of its scales with a camera housing, from smallest text to More Space.
/// In the panel's 2,880 pixels across, the housing is 312 by 56 pixels at x 1,284 at every one; macOS rounds its edges to
/// the nearest half point and its height up to the next.
let fifteenInchAir: [MeasuredScale] = [
    MeasuredScale(screen: CGSize(width: 1024, height: 663), safeAreaTop: 20, leftAreaMaxX: 456.5, rightAreaMinX: 567.5, panelPixels: 2880),
    MeasuredScale(screen: CGSize(width: 1280, height: 828), safeAreaTop: 25, leftAreaMaxX: 570.5, rightAreaMinX: 709.5, panelPixels: 2880),
    MeasuredScale(screen: CGSize(width: 1440, height: 932), safeAreaTop: 28, leftAreaMaxX: 642, rightAreaMinX: 798, panelPixels: 2880),
    MeasuredScale(screen: CGSize(width: 1710, height: 1107), safeAreaTop: 33.5, leftAreaMaxX: 762.5, rightAreaMinX: 947.5, panelPixels: 2880),
    MeasuredScale(screen: CGSize(width: 1920, height: 1243), safeAreaTop: 37.5, leftAreaMaxX: 856, rightAreaMinX: 1064, panelPixels: 2880),
]
