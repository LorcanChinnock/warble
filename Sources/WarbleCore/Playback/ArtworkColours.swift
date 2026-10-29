import CoreGraphics
import Foundation
import ImageIO

/// Two colours picked from a track's artwork, or from the playing app's icon when there's none, for the glow in the
/// expanded card. Picking decodes a small thumbnail and reads every pixel, so run it off the main thread.
public struct ArtworkColours: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The largest channel, HSB's brightness.
        var brightness: Double { max(red, green, blue) }

        var saturation: Double {
            let brightness = brightness
            return brightness == 0 ? 0 : (brightness - min(red, green, blue)) / brightness
        }

        /// The same hue scaled up to `brightness`, so a dark colour still shows against black.
        func brightened(to brightness: Double) -> RGB {
            let current = self.brightness
            guard current < brightness else { return self }
            guard current > 0 else { return RGB(red: brightness, green: brightness, blue: brightness) }
            let scale = brightness / current
            return RGB(red: red * scale, green: green * scale, blue: blue * scale)
        }

        /// WCAG's relative luminance, from 0 for black to 1 for white.
        var luminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        /// The same hue scaled down until its luminance is at most `luminance`.
        func dimmed(to luminance: Double) -> RGB {
            guard self.luminance > luminance else { return self }
            // Luminance rises with the scale, so halve the range around it until it's close enough.
            var low = 0.0
            var high = 1.0
            for _ in 0..<20 {
                let middle = (low + high) / 2
                if RGB(red: red * middle, green: green * middle, blue: blue * middle).luminance > luminance {
                    high = middle
                } else {
                    low = middle
                }
            }
            return RGB(red: red * low, green: green * low, blue: blue * low)
        }

        /// The same hue mixed with white until its luminance is at least `luminance`, so a dark colour stays recognisable
        /// but reads against black. A colour that already clears it is returned as is.
        func lightened(to luminance: Double) -> RGB {
            guard self.luminance < luminance else { return self }
            var low = 0.0
            var high = 1.0
            for _ in 0..<20 {
                let middle = (low + high) / 2
                let mixed = RGB(red: red + (1 - red) * middle, green: green + (1 - green) * middle, blue: blue + (1 - blue) * middle)
                if mixed.luminance < luminance {
                    low = middle
                } else {
                    high = middle
                }
            }
            return RGB(red: red + (1 - red) * high, green: green + (1 - green) * high, blue: blue + (1 - blue) * high)
        }

        func distance(to other: RGB) -> Double {
            ((red - other.red) * (red - other.red) + (green - other.green) * (green - other.green) + (blue - other.blue) * (blue - other.blue)).squareRoot()
        }
    }

    /// The artwork's most prominent colour, favouring vivid ones over the black, white and greys around them.
    public var first: RGB
    /// The next most prominent colour that's clearly different from `first`, or a darker `first` when there's none.
    public var second: RGB

    public init(first: RGB, second: RGB) {
        self.first = first
        self.second = second
    }

    /// The solid border drawn instead of the glow while Increase Contrast is on: `first`, bright enough to stand out.
    public var border: RGB { first.brightened(to: 0.8) }

    /// The artwork's colour for text and the bars on the black notch: `first`, lightened until it has WCAG's 4.5:1
    /// against black, or 7:1 with Increase Contrast. A dark or muddy cover gives a paler tint of its own hue, and a black
    /// one gives a plain grey, so it is never harder to read than the white it replaces.
    public func text(increasedContrast: Bool) -> RGB {
        // Against black, contrast is (luminance + 0.05) / 0.05.
        first.lightened(to: (increasedContrast ? 7 : 4.5) * 0.05 - 0.05)
    }

    /// Picks the colours from encoded artwork, or `nil` when it can't be decoded or has no opaque pixels.
    public init?(data: Data) {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.side,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        self.init(image: image)
    }

    /// Picks the colours from an image, such as an app's icon, or `nil` when it has no opaque pixels.
    public init?(image: CGImage) {
        let side = Self.side
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        // Group the pixels into buckets of similar colour, three bits a channel, and average each bucket.
        var buckets: [Int: (red: Double, green: Double, blue: Double, count: Int)] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3])
            // Mostly transparent pixels, such as the space around an icon, aren't part of it.
            guard alpha >= 128 else { continue }
            let red = Double(pixels[offset]) / alpha
            let green = Double(pixels[offset + 1]) / alpha
            let blue = Double(pixels[offset + 2]) / alpha
            let key = Int(min(red, 1) * 7.99) << 6 | Int(min(green, 1) * 7.99) << 3 | Int(min(blue, 1) * 7.99)
            let bucket = buckets[key, default: (0, 0, 0, 0)]
            buckets[key] = (bucket.red + red, bucket.green + green, bucket.blue + blue, bucket.count + 1)
        }
        let ranked = buckets.values
            .map { bucket in
                let count = Double(bucket.count)
                let colour = RGB(red: bucket.red / count, green: bucket.green / count, blue: bucket.blue / count)
                return (colour: colour, score: count * Self.weight(colour))
            }
            .sorted { $0.score > $1.score }
        guard let first = ranked.first?.colour else { return nil }
        let second = ranked.first { $0.colour.distance(to: first) >= Self.distinct }?.colour
            ?? RGB(red: first.red * 0.6, green: first.green * 0.6, blue: first.blue * 0.6)
        self.first = first.dimmed(to: Self.brightest)
        self.second = second.dimmed(to: Self.brightest)
    }

    /// The thumbnail's side in pixels: enough to find the main colours, few enough to read in well under a millisecond.
    private static let side = 32
    /// How far apart, in RGB from 0 to 1, two colours must be to count as different.
    private static let distinct = 0.3
    /// The most luminance a colour may have, so the grey symbols in the card's bottom corners keep 3:1 contrast over the
    /// glow even when the artwork is white. Vivid colours are well below it and keep their brightness.
    private static let brightest = 0.6

    /// How much a pixel of `colour` counts: vivid colours most, and near-black, which disappears into the notch, least.
    private static func weight(_ colour: RGB) -> Double {
        let brightness = colour.brightness
        return (colour.saturation + 0.1) * (brightness < 0.15 ? 0.05 : brightness)
    }
}
