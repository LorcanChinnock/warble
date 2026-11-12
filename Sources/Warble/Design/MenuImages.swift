import AppKit
import WarbleModel

extension NSImage {
    /// The app icon's bars as a template image, so macOS tints it for light and dark menu bars and while the menu is
    /// open. Drawn on demand, so it's sharp at every scale.
    static let menuBarIcon = menuBarIcon(dot: false)

    /// The bars with a waiting update's dot at the top right. The dot is part of the template, so it takes the menu
    /// bar's own text colour like the bars, and the ring around it is cut out, so it shows the menu bar's colour in
    /// light and dark, behind a tinted or translucent menu bar too.
    static let menuBarIconWithDot = menuBarIcon(dot: true)

    private static func menuBarIcon(dot: Bool) -> NSImage {
        let height: CGFloat = 16
        let bars = IconBars.rects(height: height)
        // A 6 pt dot with a 1.5 pt ring, up and to the right of the short bar like a badge, rather than straight above
        // it, where the two read as an "i". Its ring clears the bars, but is cut out anyway in case they change.
        let dotRadius: CGFloat = 3, ring: CGFloat = 1.5
        let centre = CGPoint(x: bars.last!.maxX + 1.5, y: height - dotRadius)
        let width = dot ? centre.x + dotRadius : bars.last!.maxX
        let image = NSImage(size: CGSize(width: width, height: height), flipped: false) { _ in
            for bar in bars {
                NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            }
            if dot {
                let context = NSGraphicsContext.current
                context?.compositingOperation = .clear
                NSBezierPath(ovalIn: circle(centre, dotRadius + ring)).fill()
                context?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: circle(centre, dotRadius)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The accent dot after a waiting update's menu item: the icon's yellow, with the spec's accent edge, 0.5 pt of 28%
    /// black, in the light appearance only. Drawn for whichever appearance the menu has.
    static let updateDot: NSImage = {
        let size: CGFloat = 7
        let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect)
            (NSColor(named: "Yellow") ?? .systemYellow).setFill()
            path.fill()
            if NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .aqua {
                let edge = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
                edge.lineWidth = 0.5
                NSColor.black.withAlphaComponent(0.28).setStroke()
                edge.stroke()
            }
            return true
        }
        image.accessibilityDescription = nil
        return image
    }()

    private static func circle(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}
