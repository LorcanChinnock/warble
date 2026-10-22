import Foundation
import Synchronization
import Testing
@testable import WarbleCore

private let grace = LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace", album: "Amazing Grace", duration: 172)
private let fair = LyricsQuery(artist: "Mat Williams", title: "Scarborough Fair", album: nil, duration: nil)
private let synced = "[00:10.00] Amazing grace, how sweet the sound\n[00:16.00] That saved a wretch like me\n[00:22.00]"

/// What the stub answers a request with.
private struct Reply: Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static func lyrics(_ synced: String?, instrumental: Bool = false) -> Reply {
        let answer: [String: Any] = [
            "id": 34648095, "trackName": "Amazing Grace", "artistName": "Dave Fenley", "instrumental": instrumental,
            "plainLyrics": synced == nil ? NSNull() : "Amazing grace", "syncedLyrics": synced ?? NSNull(),
        ]
        return Reply(status: 200, body: try! JSONSerialization.data(withJSONObject: answer))
    }
}

/// A pretend LRCLIB for one test: it records each request and answers with `reply`, after `delay`. Each has a session
/// of its own, told apart by a header, so tests running at once don't answer each other's.
private final class Server: Sendable {
    private struct State {
        var requests: [URLRequest] = []
        var replies: [Reply] = []
        var inFlight = 0
        var mostInFlight = 0
    }

    let id = UUID().uuidString
    let delay: TimeInterval
    private let state = Mutex(State())

    init(_ replies: Reply..., delay: TimeInterval = 0) {
        self.delay = delay
        state.withLock { $0.replies = replies }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var mostInFlight: Int { state.withLock { $0.mostInFlight } }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = [StubProtocol.header: id]
        StubProtocol.servers.withLock { $0[id] = self }
        return URLSession(configuration: configuration)
    }

    /// The next reply, or the last again once they run out.
    fileprivate func start(_ request: URLRequest) -> Reply {
        state.withLock {
            $0.requests.append(request)
            $0.inFlight += 1
            $0.mostInFlight = max($0.mostInFlight, $0.inFlight)
            return $0.replies.count > 1 ? $0.replies.removeFirst() : $0.replies[0]
        }
    }

    fileprivate func finish() {
        state.withLock { $0.inFlight -= 1 }
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let header = "X-Test-Server"
    static let servers = Mutex<[String: Server]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header), let server = Self.servers.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let reply = server.start(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + server.delay) { [self] in
            server.finish()
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// A clock that moves only when the client sleeps, and records how long it slept.
private final class SleepingClock: WallClock {
    private let state = Mutex((now: Date(timeIntervalSince1970: 1_000_000), slept: [TimeInterval]()))

    var now: Date { state.withLock { $0.now } }
    var slept: [TimeInterval] { state.withLock { $0.slept } }

    func sleep(_ seconds: TimeInterval) {
        state.withLock {
            $0.now += seconds
            $0.slept.append(seconds)
        }
    }
}

private func client(_ server: Server, cache: URL, clock: SleepingClock = SleepingClock()) -> LRCLIBClient {
    LRCLIBClient(session: server.session, cache: cache, version: "1.2.3", clock: clock, sleep: { clock.sleep($0) })
}

@Test func theRequestAsksForTheTracksArtistTitleAlbumAndLength() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced))
    _ = await client(server, cache: cache).lyrics(for: grace)
    let request = try #require(server.requests.first)
    let url = try #require(request.url)
    #expect(url.host() == "lrclib.net")
    #expect(url.path() == "/api/get")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) }) == [
        "artist_name": "Dave Fenley", "track_name": "Amazing Grace", "album_name": "Amazing Grace", "duration": "172",
    ])
}

@Test func everyRequestSaysItsFromWarble() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced))
    _ = await client(server, cache: cache).lyrics(for: grace)
    #expect(server.requests.first?.value(forHTTPHeaderField: "User-Agent") == "Warble/1.2.3 (https://warble.lorcanchinnock.com)")
}

@Test func aQueryWithoutAnAlbumOrLengthLeavesThemOutOfTheRequest() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced))
    _ = await client(server, cache: cache).lyrics(for: fair)
    let url = try #require(server.requests.first?.url)
    let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name)
    #expect(names == ["artist_name", "track_name"])
}

@Test func aPlusInATitleIsSentAsAPlusNotASpace() throws {
    let client = LRCLIBClient(session: .shared, cache: FileManager.default.temporaryDirectory, version: "1")
    let url = try #require(client.request(for: LyricsQuery(artist: "Me & You", title: "One + One")).url)
    #expect(url.query(percentEncoded: true) == "artist_name=Me%20%26%20You&track_name=One%20%2B%20One")
}

@Test func syncedLyricsAreReturnedAndCached() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced))
    let lyrics = client(server, cache: cache)
    #expect(await lyrics.lyrics(for: grace) == synced)
    #expect(await lyrics.lyrics(for: grace) == synced)
    #expect(await client(server, cache: cache).lyrics(for: grace) == synced)
    #expect(server.requests.count == 1)
}

@Test func aTrackLRCLIBDoesntKnowHasNoLyricsAndIsntAskedForAgain() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(Reply(status: 404))
    let lyrics = client(server, cache: cache)
    #expect(await lyrics.lyrics(for: grace) == nil)
    #expect(await client(server, cache: cache).lyrics(for: grace) == nil)
    #expect(server.requests.count == 1)
}

@Test func noLyricsIsAskedForAgainAfterThirtyDays() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(Reply(status: 404), .lyrics(synced))
    let clock = SleepingClock()
    let lyrics = client(server, cache: cache, clock: clock)
    #expect(await lyrics.lyrics(for: grace) == nil)
    clock.sleep(LRCLIBClient.noLyricsExpiry - 1)
    #expect(await lyrics.lyrics(for: grace) == nil)
    #expect(server.requests.count == 1)
    clock.sleep(1)
    #expect(await lyrics.lyrics(for: grace) == synced)
    // Lyrics found don't expire.
    clock.sleep(LRCLIBClient.noLyricsExpiry * 10)
    #expect(await lyrics.lyrics(for: grace) == synced)
    #expect(server.requests.count == 2)
}

@Test func plainLyricsOrAnInstrumentalAreNoLyricsAndArentAskedForAgain() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(nil), .lyrics(synced, instrumental: true), .lyrics(""))
    let lyrics = client(server, cache: cache)
    let queries = [grace, fair, LyricsQuery(artist: "Dave Fenley", title: "Amazing Grace")]
    for query in queries {
        #expect(await lyrics.lyrics(for: query) == nil)
        #expect(await lyrics.lyrics(for: query) == nil)
    }
    #expect(server.requests.count == queries.count)
}

@Test func lyricsTooLongForAnySongAreNoLyrics() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let line = "[00:10.00] Amazing grace, how sweet the sound\n"
    let server = Server(.lyrics(String(repeating: line, count: LRCLIBClient.largestLyrics / line.utf8.count + 1)))
    #expect(await client(server, cache: cache).lyrics(for: grace) == nil)
}

@Test func aFailureIsNothingAndIsAskedForAgain() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let busy = Data(#"{"code":503,"name":"ServerOverloaded","message":"The server is busy, please retry in a moment"}"#.utf8)
    let server = Server(Reply(status: 503, body: busy), Reply(status: 200, body: Data("<html>".utf8)), Reply(status: 500), .lyrics(synced))
    let lyrics = client(server, cache: cache)
    for _ in 1...3 {
        #expect(await lyrics.lyrics(for: grace) == nil)
    }
    #expect(await lyrics.lyrics(for: grace) == synced)
    #expect(server.requests.count == 4)
}

@Test func noConnectionIsNothing() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let lyrics = LRCLIBClient(session: URLSession(configuration: configuration), cache: cache, version: "1")
    #expect(await lyrics.lyrics(for: grace) == nil)
}

@Test func aDamagedCacheFileIsAskedForAgain() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced))
    #expect(await client(server, cache: cache).lyrics(for: grace) == synced)
    for file in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) {
        try Data("{\"key\":".utf8).write(to: file)
    }
    #expect(await client(server, cache: cache).lyrics(for: grace) == synced)
    #expect(server.requests.count == 2)
}

@Test func after429TheNextRequestWaitsOutRetryAfter() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(Reply(status: 429, headers: ["Retry-After": "30"]), .lyrics(synced))
    let clock = SleepingClock()
    let lyrics = client(server, cache: cache, clock: clock)
    #expect(await lyrics.lyrics(for: grace) == nil)
    #expect(clock.slept == [])
    #expect(await lyrics.lyrics(for: grace) == synced)
    #expect(clock.slept == [30])
    #expect(await lyrics.lyrics(for: fair) == synced)
    #expect(clock.slept == [30])
    #expect(server.requests.count == 3)
}

@Test func retryAfterIsReadAsSecondsOrADateAndKeptWithinFiveMinutes() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    #expect(LRCLIBClient.wait(retryAfter: "12", now: now) == 12)
    #expect(LRCLIBClient.wait(retryAfter: "Sun, 09 Sep 2001 01:47:00 GMT", now: now) == 20)
    #expect(LRCLIBClient.wait(retryAfter: "Sun, 09 Sep 2001 01:00:00 GMT", now: now) == 0)
    #expect(LRCLIBClient.wait(retryAfter: "-5", now: now) == 0)
    for header in ["99999999999999999999", "1e400", "Fri, 31 Dec 9999 23:59:59 GMT"] {
        #expect(LRCLIBClient.wait(retryAfter: header, now: now) == LRCLIBClient.longestWait)
    }
    for header in [nil, "", "soon", "nan"] {
        #expect(LRCLIBClient.wait(retryAfter: header, now: now) == LRCLIBClient.defaultWait)
    }
}

@Test func twoCallsAtOnceGoOneAfterTheOther() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced), delay: 0.1)
    let lyrics = client(server, cache: cache)
    async let first = lyrics.lyrics(for: grace)
    async let second = lyrics.lyrics(for: fair)
    #expect(await [first, second] == [synced, synced])
    #expect(server.requests.count == 2)
    #expect(server.mostInFlight == 1)
}

@Test func twoCallsAtOnceForOneTrackAskOnce() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced), delay: 0.1)
    let lyrics = client(server, cache: cache)
    async let first = lyrics.lyrics(for: grace)
    async let second = lyrics.lyrics(for: grace)
    #expect(await [first, second] == [synced, synced])
    #expect(server.requests.count == 1)
}

@Test func aCallStillWaitingWhenANewerOneIsAskedForSendsNothing() async throws {
    let cache = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cache) }
    let server = Server(.lyrics(synced), delay: 0.5)
    let lyrics = client(server, cache: cache)
    let skipped = LyricsQuery(artist: "Traditional", title: "Greensleeves", album: "Folk", duration: 150)
    // Each a moment after the one before, so they're asked in order while the first is in flight.
    let first = Task { await lyrics.lyrics(for: grace) }
    try await Task.sleep(for: .milliseconds(100))
    let second = Task { await lyrics.lyrics(for: skipped) }
    try await Task.sleep(for: .milliseconds(100))
    let third = Task { await lyrics.lyrics(for: fair) }
    #expect(await [first.value, second.value, third.value] == [synced, nil, synced])
    let titles = server.requests.compactMap { request in
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "track_name" }?.value }
    }
    #expect(titles == ["Amazing Grace", "Scarborough Fair"])
    #expect(server.requests.count == 2)
}
