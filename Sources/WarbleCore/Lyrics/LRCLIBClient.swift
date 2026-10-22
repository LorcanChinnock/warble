import CryptoKit
import Foundation

/// Fetches a track's synced lyrics from LRCLIB (lrclib.net) and keeps each answer in a cache on disk, "no lyrics"
/// included, so a track is asked for once. The cache is the only place lyrics are kept, and clearing it is safe.
///
/// Requests go one at a time, in the order they're asked for, and after a 429 the next waits out `Retry-After`. A
/// request that fails, by a 503 or no network, returns nothing and is asked again next time.
public actor LRCLIBClient {
    public static let endpoint = URL(string: "https://lrclib.net/api/get")!
    /// The longest Warble waits after a 429, whatever `Retry-After` says, and how long it waits when it says nothing.
    static let longestWait: TimeInterval = 300
    static let defaultWait: TimeInterval = 60
    /// Longer synced lyrics than this are taken as none. A ten-minute song's are about 10 KB.
    static let largestLyrics = 256 * 1024

    private let session: URLSession
    private let cache: URL
    private let userAgent: String
    private let clock: any WallClock
    private let sleep: @Sendable (TimeInterval) async -> Void
    /// The last request asked for, which the next waits on.
    private var queue: Task<Void, Never>?
    /// When the next request may go, after a 429.
    private var notBefore: Date?

    /// `cache` is a folder of its own, created when the first answer is saved. `version` is Warble's, sent in the
    /// `User-Agent` as LRCLIB asks.
    public init(
        session: URLSession,
        cache: URL,
        version: String,
        clock: any WallClock = SystemClock(),
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.session = session
        self.cache = cache
        self.userAgent = "Warble/\(version) (https://warble.lorcanchinnock.com)"
        self.clock = clock
        self.sleep = sleep
    }

    /// The cache in `Lyrics` in Warble's folder in Caches, one for each bundle identifier, so a dev build keeps its own.
    public static func standard(bundleIdentifier: String, version: String, session: URLSession = .shared) -> LRCLIBClient? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent("Lyrics", isDirectory: true)
        return LRCLIBClient(session: session, cache: folder, version: version)
    }

    /// The track's synced lyrics as LRC text, or `nil` when LRCLIB has none or the request fails.
    public func lyrics(for query: LyricsQuery) async -> String? {
        if let cached = cached(query) { return cached.lrc }
        let previous = queue
        let request = Task {
            await previous?.value
            return await self.fetch(query)
        }
        queue = Task { _ = await request.value }
        return await request.value
    }

    /// The request for `query`. `+` is escaped too, since LRCLIB reads it in a query as a space.
    nonisolated func request(for query: LyricsQuery) -> URLRequest {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "track_name", value: query.title),
        ] + [
            query.album.map { URLQueryItem(name: "album_name", value: $0) },
            query.duration.map { URLQueryItem(name: "duration", value: String($0)) },
        ].compactMap { $0 }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func fetch(_ query: LyricsQuery) async -> String? {
        // A call for the same track may have been answered while this one waited.
        if let cached = cached(query) { return cached.lrc }
        if let notBefore {
            // Bounded again in case the clock has moved back since.
            let wait = min(notBefore.timeIntervalSince(clock.now), Self.longestWait)
            if wait > 0 { await sleep(wait) }
            self.notBefore = nil
        }
        guard let (data, response) = try? await session.data(for: request(for: query)),
              let response = response as? HTTPURLResponse
        else { return nil }
        switch response.statusCode {
        case 200:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
            let lrc = answer.syncedLyrics.flatMap { lrc in
                answer.instrumental != true && !lrc.isEmpty && lrc.utf8.count <= Self.largestLyrics ? lrc : nil
            }
            save(Entry(key: query.cacheKey, lrc: lrc))
            return lrc
        case 404:
            save(Entry(key: query.cacheKey, lrc: nil))
            return nil
        case 429:
            let now = clock.now
            notBefore = now.addingTimeInterval(Self.wait(retryAfter: response.value(forHTTPHeaderField: "Retry-After"), now: now))
            return nil
        default:
            return nil
        }
    }

    /// How long `Retry-After` asks to wait, in seconds or until an HTTP date, kept between none and `longestWait`.
    static func wait(retryAfter header: String?, now: Date) -> TimeInterval {
        guard let header = header?.trimmingCharacters(in: .whitespaces) else { return defaultWait }
        let seconds: TimeInterval
        if let value = Double(header), !value.isNaN {
            seconds = value
        } else if let date = httpDate().date(from: header) {
            seconds = date.timeIntervalSince(now)
        } else {
            return defaultWait
        }
        return min(max(seconds, 0), longestWait)
    }

    /// Made for each 429 rather than kept, since a `DateFormatter` isn't `Sendable` and a 429 is rare.
    private static func httpDate() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }

    // MARK: Cache

    /// One file for each query, named for a hash of its key. The file holds the key too, so two keys with the same hash
    /// can't answer for each other.
    private struct Entry: Codable {
        var key: String
        /// `nil` when LRCLIB has no synced lyrics for the track.
        var lrc: String?
    }

    private struct Answer: Decodable {
        var instrumental: Bool?
        var syncedLyrics: String?
    }

    private func file(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cache.appendingPathComponent("\(hash).json")
    }

    /// The cached answer for `query`, or `nil` when there's none or it can't be read.
    private func cached(_ query: LyricsQuery) -> Entry? {
        let key = query.cacheKey
        guard let data = try? Data(contentsOf: file(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.key == key
        else { return nil }
        return entry
    }

    /// Saves `entry`, or doesn't if the disk refuses: the track is then asked for again next time.
    private func save(_ entry: Entry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try? data.write(to: file(for: entry.key), options: .atomic)
    }
}
