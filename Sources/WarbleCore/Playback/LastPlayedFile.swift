import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps the last track played in a small file, so the idle card still shows it after Warble opens again. Reading and
/// writing touch the disk, so call them off the main thread.
public struct LastPlayedFile: LastPlayedStore {
    /// The longest side of the art it keeps, in pixels: the largest the notch draws it, 56 points, at 2×.
    public static let artworkPixels = 112

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `LastPlayed.json` in Warble's folder in Application Support, one for each bundle identifier, so a dev build
    /// keeps its own.
    public static func standard(bundleIdentifier: String) -> LastPlayedFile? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent(bundleIdentifier, isDirectory: true)
        return LastPlayedFile(url: folder.appendingPathComponent("LastPlayed.json"))
    }

    /// The saved track, or `nil` when none was saved or the file can't be read.
    public func load() -> LastPlayed? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LastPlayed.self, from: data)
    }

    public func save(_ lastPlayed: LastPlayed) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(lastPlayed).write(to: url, options: .atomic)
    }

    public func remembering(_ state: PlaybackState, appName: String?) -> LastPlayed {
        Self.remembering(state, appName: appName)
    }

    /// `state` as it's remembered, with its art shrunk to `artworkPixels` on its longest side.
    public static func remembering(_ state: PlaybackState, appName: String?) -> LastPlayed {
        LastPlayed(
            bundleIdentifier: state.bundleIdentifier,
            appName: appName,
            title: state.title,
            artist: state.artist,
            artwork: state.artwork.flatMap { thumbnail($0, pixels: artworkPixels) }
        )
    }

    /// `data`, an encoded image, as a JPEG no more than `pixels` on its longest side, or `nil` when it isn't an image.
    public static func thumbnail(_ data: Data, pixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Keeps the last track played only while Warble runs, as the preview does, so it neither reads nor saves the real one.
public struct LastPlayedInMemory: LastPlayedStore {
    public init() {}

    public func load() -> LastPlayed? { nil }

    public func save(_ lastPlayed: LastPlayed) throws {}

    public func remembering(_ state: PlaybackState, appName: String?) -> LastPlayed {
        LastPlayedFile.remembering(state, appName: appName)
    }
}
