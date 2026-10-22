// Renders Resources/AppIcon.icns and docs/icon.png (for the README). Run: make icon, which adds
// Sources/WarbleModel/Design/IconBars.swift for the bars the menu bar icon shares.
import AppKit

let tileTop = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
let tileBottom = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
let housing = NSColor.black
let mark = NSColor.white
let glow = NSColor(srgbRed: 1, green: 0.48, blue: 0.71, alpha: 1)

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
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    tileBottom.setFill()
    tile.fill()
    ctx.restoreGState()
    NSGradient(starting: tileTop, ending: tileBottom)!.draw(in: tile, angle: -90)

    // The camera housing at the top edge, pure black as on the Mac, with the glow the open card takes from the
    // artwork behind the middle bar and three white bars below it.
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
    housing.setFill()
    notch.fill()
    let accentBar = IconBars.rects[IconBars.accent]
    NSGradient(colors: [glow.withAlphaComponent(0.55), glow.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: accentBar.midX, y: accentBar.midY), radius: 0, toCenter: CGPoint(x: accentBar.midX, y: accentBar.midY), radius: 330, options: [])
    ctx.restoreGState()

    for rect in IconBars.rects {
        mark.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
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
