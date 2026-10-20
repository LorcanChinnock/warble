#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// When a display without a camera housing draws a notch of its own.
public enum VirtualNotchRule: String, CaseIterable, Sendable {
    case off
    case always
    /// Only while no display has a camera housing: a MacBook's lid is closed, or the Mac has no notch at all.
    case noNotch

    /// What a display follows until it's given a rule: the main display stands in for the built-in notch when that's
    /// closed or missing, and every other display draws nothing.
    public static func `default`(isMain: Bool) -> Self {
        isMain ? .noNotch : .off
    }
}

/// A display as the notch sees it. All rects are in AppKit space.
public struct NotchDisplay: Equatable, Sendable {
    /// Stays the same across launches and reconnections, so a rule follows its display.
    public var id: String
    public var frame: CGRect
    public var menuBarHeight: CGFloat
    /// The camera housing, or `nil` on a display without one.
    public var notch: CGRect?
    /// The display with the menu bar in System Settings › Displays, first in `NSScreen.screens`.
    public var isMain: Bool

    public init(id: String, frame: CGRect, menuBarHeight: CGFloat, notch: CGRect?, isMain: Bool) {
        self.id = id
        self.frame = frame
        self.menuBarHeight = menuBarHeight
        self.notch = notch
        self.isMain = isMain
    }
}

/// A camera housing, real or virtual, that Warble draws its notch over.
public struct NotchHousing: Equatable, Sendable {
    /// The `NotchDisplay.id` of the display it's on.
    public var display: String
    public var frame: CGRect
    public var isVirtual: Bool

    public init(display: String, frame: CGRect, isVirtual: Bool) {
        self.display = display
        self.frame = frame
        self.isVirtual = isVirtual
    }
}

/// Where Warble draws a notch: over each camera housing, and at the top centre of each display whose rule asks for one.
public enum VirtualNotch {
    /// A little narrower than a MacBook's housing, about 185 points, so the panel doesn't feel too wide on a display
    /// that has no camera to hide.
    public static let width: CGFloat = 160
    /// The height when the menu bar hides itself and so measures 0, the height of a menu bar without a notch.
    public static let fallbackHeight: CGFloat = 24

    /// The housing a display without a notch draws: centred at the top, as tall as its menu bar. The left edge is a
    /// whole point, since AppKit snaps windows to whole points and the shape would otherwise sit half a point off.
    public static func housing(in frame: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let height = menuBarHeight > 0 ? menuBarHeight : fallbackHeight
        return CGRect(x: (frame.midX - width / 2).rounded(), y: frame.maxY - height, width: width, height: height)
    }

    /// The housings to draw over, in the order of `displays`: the real one where there is one, and a virtual one where
    /// the display's rule in `rules`, or its default, says so.
    public static func housings(_ displays: [NotchDisplay], rules: [String: VirtualNotchRule]) -> [NotchHousing] {
        let noNotch = !displays.contains { $0.notch != nil }
        return displays.compactMap { display in
            if let notch = display.notch {
                return NotchHousing(display: display.id, frame: notch, isVirtual: false)
            }
            switch rules[display.id] ?? .default(isMain: display.isMain) {
            case .off: return nil
            case .noNotch where !noNotch: return nil
            case .always, .noNotch:
                let frame = housing(in: display.frame, menuBarHeight: display.menuBarHeight)
                return NotchHousing(display: display.id, frame: frame, isVirtual: true)
            }
        }
    }
}
