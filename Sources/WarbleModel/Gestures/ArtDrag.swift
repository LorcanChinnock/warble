import Foundation

/// What dragging the art out of the player's card carries: the track's link where the player gives one, with the image as
/// well, or the image alone. Settings turns it on.
public struct ArtDrag: Equatable, Sendable {
    public var link: URL?
    /// The art's encoded bytes, PNG, JPEG or TIFF, and the name of the file it drops as in Finder.
    public var image: Data?
    public var fileName: String?

    /// What dragging `playback`'s art carries, or `nil` when there's nothing to drag: no link and no art.
    public init?(_ playback: PlaybackState) {
        guard playback.link != nil || playback.artwork != nil else { return nil }
        link = playback.link
        image = playback.artwork
        fileName = playback.artwork.map { Self.fileName(title: playback.title, image: $0) }
    }

    /// The track's title, with the characters Finder can't take swapped out, and the extension the bytes call for.
    static func fileName(title: String, image: Data) -> String {
        let name = title
            .map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespaces)
            // A name that starts with a dot is hidden in Finder.
            .drop { $0 == "." }
        return "\(name.isEmpty ? "Artwork" : String(name.prefix(200))).\(fileExtension(of: image))"
    }

    /// The extension for an image's bytes, by the signature they start with. Sources report PNG, JPEG or TIFF.
    static func fileExtension(of image: Data) -> String {
        if image.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if image.starts(with: [0x49, 0x49, 0x2A, 0x00]) || image.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return "jpg"
    }
}
