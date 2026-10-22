import AppKit

/// A made-up track. Its art is drawn from `hue`, so the demo ships no images and no one else's artwork.
struct Track {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let hue: CGFloat

    static let all = [
        Track(title: "Paper Lanterns", artist: "Juniper Hale", album: "Slow Weather", duration: 214, hue: 0.92),
        Track(title: "Low Tide Radio", artist: "The Quiet Engines", album: "Harbour Lights", duration: 187, hue: 0.55),
        Track(title: "Orchard Hours", artist: "Mina Sol", album: "Greenhouse", duration: 242, hue: 0.33),
        Track(title: "Static Bloom", artist: "Kestrel & Vale", album: "Afterimage", duration: 199, hue: 0.75),
    ]

    /// A soft two-colour gradient with a ring, 600 points square.
    func artwork() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            let top = NSColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1)
            let bottom = NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.45, alpha: 1)
            NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -60)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 170, dy: 170))
            ring.lineWidth = 26
            ring.stroke()
            return true
        }
    }
}
