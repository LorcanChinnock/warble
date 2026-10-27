import Foundation
import os
import WarbleModel
import Synchronization

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "cover-art")

/// Swaps the picture a browser reports, which is a frame of the video, for the song's album cover from the iTunes Search
/// API. Only tracks from a browser are looked up, and each song once: the answer is kept, including "no match", so
/// pausing or seeking never searches again. Until the answer comes the track has no artwork, so the video frame never
/// shows; with no match, the browser's own picture stays.
public enum CoverArt {
    /// What a lookup searches for.
    public struct Query: Hashable, Sendable {
        public var title: String
        public var artist: String?

        public init(title: String, artist: String?) {
            self.title = title
            self.artist = artist
        }

        init?(_ state: PlaybackState) {
            guard Self.browsers.contains(state.bundleIdentifier), !state.title.isEmpty else { return nil }
            self.init(title: state.title, artist: state.artist)
        }

        private static let browsers: Set<String> = [
            "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
            "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.mozilla.firefox", "com.operasoftware.Opera",
        ]
    }

    /// `states` with each browser track's artwork replaced as above. `cover` finds the cover's bytes, and is the real
    /// lookup unless a test passes its own.
    public static func replacing(
        _ states: AsyncStream<PlaybackState?>,
        cover: @escaping @Sendable (Query) async -> Data? = CoverArt.fetch
    ) -> AsyncStream<PlaybackState?> {
        let (output, continuation) = AsyncStream<PlaybackState?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let shared = Locked()
        let task = Task {
            for await state in states {
                let (shown, lookup) = shared.withLock { shared in
                    shared.latest = state
                    let query = state.flatMap(Query.init)
                    let needsLookup = query.map { shared.covers[$0] == nil && shared.pending.insert($0).inserted } ?? false
                    return (shared.shown(), needsLookup ? query : nil)
                }
                continuation.yield(shown)
                guard let lookup else { continue }
                Task {
                    let data = await cover(lookup)
                    let shown = shared.withLock { shared -> PlaybackState?? in
                        shared.pending.remove(lookup)
                        if shared.covers.count >= 50 {
                            shared.covers.removeAll()
                        }
                        shared.covers[lookup] = data.map(Shared.Cover.found) ?? .missing
                        // A newer track has its own lookup, and its own report to show.
                        return shared.latest.flatMap(Query.init) == lookup ? .some(shared.shown()) : nil
                    }
                    if let shown {
                        continuation.yield(shown)
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return output
    }

    /// `Shared` behind a lock, in a class so the lookups' tasks can hold it; a `Mutex` itself can't be captured.
    private final class Locked: Sendable {
        private let mutex = Mutex(Shared())

        func withLock<R>(_ body: (inout Shared) -> R) -> R {
            mutex.withLock { body(&$0) }
        }
    }

    private struct Shared {
        enum Cover {
            case found(Data)
            case missing
        }

        /// The last report as the source sent it.
        var latest: PlaybackState?
        var covers: [Query: Cover] = [:]
        var pending: Set<Query> = []

        /// `latest` with the cover for its track, or no artwork while the cover is still being looked up.
        func shown() -> PlaybackState? {
            guard var state = latest, let query = Query(state) else { return latest }
            switch covers[query] {
            case .found(let data): state.artwork = data
            case .missing: break
            case nil: state.artwork = nil
            }
            return state
        }
    }

    // MARK: - The lookup

    /// The search for `query`: songs, a few results, so a wrong first hit can still be skipped.
    static func searchURL(for query: Query) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: [query.artist, query.title].compactMap { $0 }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        return components?.url
    }

    /// The cover's address in a search response: the first result whose song and artist both appear in what the browser
    /// reported, since a video title often reads "Artist - Song (Official Video)". Asks for a 600 pixel image, as the
    /// response only links a 100 pixel one.
    static func coverURL(in response: Data, for query: Query) -> URL? {
        struct Response: Decodable {
            struct Result: Decodable {
                var trackName: String?
                var artistName: String?
                var artworkUrl100: String?
            }
            var results: [Result]
        }
        guard let results = try? JSONDecoder().decode(Response.self, from: response).results else { return nil }
        let reported = normalised([query.artist, query.title].compactMap { $0 }.joined(separator: " "))
        for result in results {
            guard let track = result.trackName.map(normalised), let artist = result.artistName.map(normalised),
                  let art = result.artworkUrl100, !track.isEmpty, !artist.isEmpty,
                  reported.contains(track), reported.contains(artist)
            else { continue }
            return URL(string: art.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
        }
        return nil
    }

    /// Lowercase letters and digits only, so "Don't Stop" and "dont stop" match.
    private static func normalised(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    /// The cover's bytes, or `nil` when nothing matches or Warble is offline.
    @Sendable public static func fetch(_ query: Query) async -> Data? {
        guard let search = searchURL(for: query) else { return nil }
        do {
            let (response, _) = try await session.data(from: search)
            guard let url = coverURL(in: response, for: query) else { return nil }
            return try await session.data(from: url).0
        } catch {
            log.error("Cover didn't download: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
