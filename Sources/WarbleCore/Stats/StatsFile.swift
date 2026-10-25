import Foundation

/// Keeps the listening stats in a file in Application Support, one JSON span to a line, so recording one is an append
/// rather than a rewrite. Nothing leaves this Mac. Reading and writing touch the disk, so call them off the main thread.
public struct StatsFile: StatsStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Stats.jsonl` in Warble's folder in Application Support, one for each bundle identifier, so a dev build keeps its own.
    public static func standard(bundleIdentifier: String) -> StatsFile? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent(bundleIdentifier, isDirectory: true)
        return StatsFile(url: folder.appendingPathComponent("Stats.jsonl"))
    }

    public func append(_ span: ListenedSpan) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = try Self.encoder.encode(span) + Data("\n".utf8)
        guard FileManager.default.fileExists(atPath: url.path) else {
            try line.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// The spans that began on or after `date`. When older ones are in the file it's rewritten without them, so it holds a
    /// month at most. A line that can't be read is skipped.
    public func load(since date: Date) -> [ListenedSpan] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let all = data.split(separator: UInt8(ascii: "\n")).compactMap { try? Self.decoder.decode(ListenedSpan.self, from: $0) }
        let kept = all.filter { $0.start >= date }
        if kept.count < all.count {
            let lines = kept.compactMap { try? Self.encoder.encode($0) + Data("\n".utf8) }
            try? Data(lines.joined()).write(to: url, options: .atomic)
        }
        return kept
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
