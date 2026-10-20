import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WarbleCore

/// An image `width` by `height` pixels, filled by `fill` for each pixel's position from the top left.
private func image(width: Int = 40, height: Int = 40, _ fill: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) throws -> CGImage {
    var pixels = [UInt8]()
    for y in 0..<height {
        for x in 0..<width {
            let (red, green, blue, alpha) = fill(x, y)
            pixels += [red, green, blue, alpha]
        }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    return try #require(CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ))
}

private func png(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func isClose(_ colour: ArtworkColours.RGB, _ red: Double, _ green: Double, _ blue: Double) -> Bool {
    colour.distance(to: ArtworkColours.RGB(red: red, green: green, blue: blue)) < 0.1
}

@Test func artworkInTwoColoursGivesBoth() throws {
    let halves = try image { x, _ in x < 24 ? (220, 30, 30, 255) : (30, 60, 220, 255) }
    let colours = try #require(ArtworkColours(data: png(halves)))
    #expect(isClose(colours.first, 0.86, 0.12, 0.12))
    #expect(isClose(colours.second, 0.12, 0.24, 0.86))
}

@Test func aVividPatchBeatsTheBlackAroundIt() throws {
    let patch = try image { x, y in (10..<20).contains(x) && (10..<20).contains(y) ? (240, 180, 20, 255) : (5, 5, 5, 255) }
    let colours = try #require(ArtworkColours(image: patch))
    #expect(isClose(colours.first, 0.94, 0.71, 0.08))
}

@Test func artworkInOneColourGivesADarkerSecond() throws {
    let solid = try image { _, _ in (40, 160, 90, 255) }
    let colours = try #require(ArtworkColours(image: solid))
    #expect(isClose(colours.first, 0.16, 0.63, 0.35))
    #expect(colours.second.brightness < colours.first.brightness)
}

@Test func paleArtworkIsDimmedSoTheGreySymbolsStillShow() throws {
    let pale = try image { x, _ in x < 24 ? (255, 255, 255, 255) : (255, 240, 120, 255) }
    let colours = try #require(ArtworkColours(image: pale))
    for colour in [colours.first, colours.second] {
        #expect(colour.luminance <= 0.6)
        #expect(colour.luminance > 0.59)
    }
    #expect(abs(colours.first.red / colours.first.blue - 255.0 / 120) < 0.05)
    #expect(abs(colours.second.red - colours.second.blue) < 0.001)
}

@Test func theSpaceAroundAnIconIsIgnored() throws {
    let icon = try image { x, y in (8..<32).contains(x) && (8..<32).contains(y) ? (200, 40, 160, 255) : (0, 0, 0, 0) }
    let colours = try #require(ArtworkColours(image: icon))
    #expect(isClose(colours.first, 0.78, 0.16, 0.63))
}

@Test func aFullyTransparentImageHasNoColours() throws {
    #expect(ArtworkColours(image: try image { _, _ in (0, 0, 0, 0) }) == nil)
}

@Test func dataThatIsntAnImageHasNoColours() {
    #expect(ArtworkColours(data: Data("not an image".utf8)) == nil)
}

@Test func theContrastBorderLiftsADarkColourAndKeepsItsHue() {
    let navy = ArtworkColours.RGB(red: 0.05, green: 0.1, blue: 0.3)
    let border = ArtworkColours(first: navy, second: navy).border
    #expect(abs(border.brightness - 0.8) < 0.001)
    #expect(abs(border.red / border.blue - navy.red / navy.blue) < 0.001)
    let bright = ArtworkColours.RGB(red: 0.9, green: 0.5, blue: 0.1)
    #expect(ArtworkColours(first: bright, second: bright).border == bright)
}
