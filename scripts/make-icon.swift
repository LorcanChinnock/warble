// Renders Resources/AppIcon.icns and docs/icon.png (for the README). Run: make icon, which adds
// Sources/WarbleModel/Design/IconBars.swift for the bars the menu bar icon shares.
import AppKit

let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
let yellow = NSColor(srgbRed: 1, green: 0.83, blue: 0.23, alpha: 1)
let yellowLight = NSColor(srgbRed: 1, green: 0.89, blue: 0.40, alpha: 1)
let pink = NSColor(srgbRed: 1, green: 0.48, blue: 0.71, alpha: 1)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt body centered with 100 pt margin.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let tile = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    yellow.setFill()
    tile.fill()
    ctx.restoreGState()
    NSGradient(starting: yellowLight, ending: yellow)!.draw(in: tile, angle: -90)

    // A notch at the top edge with three equaliser bars singing below it. A placeholder until the final mark.
    let notch = NSBezierPath()
    let notchRect = CGRect(x: body.midX - 210, y: body.maxY - 190, width: 420, height: 190)
    let corner: CGFloat = 90
    notch.move(to: CGPoint(x: notchRect.minX, y: notchRect.maxY))
    notch.line(to: CGPoint(x: notchRect.minX, y: notchRect.minY + corner))
    notch.appendArc(withCenter: CGPoint(x: notchRect.minX + corner, y: notchRect.minY + corner), radius: corner, startAngle: 180, endAngle: 270)
    notch.line(to: CGPoint(x: notchRect.maxX - corner, y: notchRect.minY))
    notch.appendArc(withCenter: CGPoint(x: notchRect.maxX - corner, y: notchRect.minY + corner), radius: corner, startAngle: 270, endAngle: 360)
    notch.line(to: CGPoint(x: notchRect.maxX, y: notchRect.maxY))
    notch.close()
    ctx.saveGState()
    tile.addClip()
    ink.setFill()
    notch.fill()
    ctx.restoreGState()

    for (index, rect) in IconBars.rects.enumerated() {
        let bar = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        (index == IconBars.accent ? pink : ink).setFill()
        bar.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try render(size: 512).write(to: root.appendingPathComponent("docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
