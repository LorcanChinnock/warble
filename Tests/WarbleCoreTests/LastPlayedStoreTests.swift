import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WarbleCore

/// A grey PNG `size` pixels square.
private func png(size: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func pixelWidth(_ data: Data) throws -> Int {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
}

@Test func theLastTrackPlayedSurvivesAReload() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = LastPlayedStore(url: folder.appendingPathComponent("Warble/LastPlayed.json"))
    #expect(store.load() == nil)
    let track = LastPlayed(bundleIdentifier: "com.apple.Music", appName: "Music", title: "Song", artist: "Artist", artwork: Data([1, 2, 3]))
    try store.save(track)
    #expect(LastPlayedStore(url: store.url).load() == track)
}

@Test func aDamagedFileLoadsAsNothingPlayedYet() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("LastPlayed.json")
    try Data("{\"title\":".utf8).write(to: url)
    #expect(LastPlayedStore(url: url).load() == nil)
}

@Test func theRememberedArtIsASmallCopy() throws {
    let state = PlaybackState(bundleIdentifier: "com.spotify.client", title: "Song", artist: "Artist", elapsedTimestamp: .now, rate: 1, artwork: try png(size: 600))
    let remembered = LastPlayedStore.remembering(state, appName: "Spotify")
    #expect(remembered.title == "Song")
    #expect(remembered.artist == "Artist")
    #expect(remembered.appName == "Spotify")
    let artwork = try #require(remembered.artwork)
    #expect(try pixelWidth(artwork) == LastPlayedStore.artworkPixels)
    #expect(artwork.count < 10_000)
}

@Test func artThatIsntAnImageIsLeftOut() {
    let state = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: .now, artwork: Data("not an image".utf8))
    #expect(LastPlayedStore.remembering(state, appName: nil).artwork == nil)
}
