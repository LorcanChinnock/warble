import Darwin
import Foundation
import Testing
import WarbleModel
@testable import WarbleCore

/// A short folder of its own, since a socket's whole path must fit in 103 bytes.
private func socketURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("agent.sock")
}

/// A server that answers each request with its arguments joined, in the error's place for `fail`.
private func echoServer(at url: URL, user: uid_t = getuid()) -> AgentSocket.Server {
    AgentSocket.Server(url: url, user: user) { request in
        request.arguments == ["fail"] ? .failure(.unavailable("no")) : .success(now: NowPlayingSnapshot(title: request.arguments.joined(separator: " ")))
    }
}

private extension NowPlayingSnapshot {
    /// A snapshot that carries a title, to tell answers apart.
    init(title: String) {
        self = NowPlayingSnapshot(AppState(), volume: nil, at: .now)
        self.title = title
    }
}

/// What a client sends and reads back: the bytes as they went, over a plain socket, as `warble` does.
private func exchange(_ bytes: Data, at url: URL, closeWriting: Bool = false) throws -> Data {
    var address = try AgentSocket.address(of: url)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { throw RemoteCommandError.unavailable("not connected: \(String(cString: strerror(errno)))") }
    AgentSocket.setTimeout(fd, SO_RCVTIMEO, .seconds(5))
    AgentSocket.keepSignalsOff(fd)
    _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    if closeWriting { shutdown(fd, SHUT_WR) }
    var answer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count > 0 else { return answer }
        answer.append(contentsOf: chunk[..<count])
        if answer.last == UInt8(ascii: "\n") { return answer }
    }
}

private func ask(_ arguments: [String], at url: URL) throws -> RemoteResponse {
    let answer = try exchange(RemoteRequest(arguments: arguments).line, at: url)
    return try RemoteResponse.decode(answer.dropLast())
}

private func permissions(_ path: String) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
}

@Test func aRequestGetsItsAnswer() throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    let response = try ask(["seek", "90"], at: url)
    #expect(response.ok)
    #expect(response.now?.title == "seek 90")
    #expect(AgentSocket.isListening(at: url))
}

@Test func theAppsErrorComesBackWithItsCode() throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    let response = try ask(["fail"], at: url)
    #expect(!response.ok)
    #expect(response.code == 69)
    #expect(response.error == "no")
}

@Test func onlyTheUserCanReachTheFolderAndTheSocket() throws {
    let url = try socketURL()
    let folder = url.deletingLastPathComponent().path
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    #expect(try permissions(folder) == 0o700)
    #expect(try permissions(url.path) == 0o600)
}

@Test func aConnectionFromAnotherUserGetsNoAnswer() throws {
    let url = try socketURL()
    // The server's user is anyone but this one, so this client counts as another user's.
    let server = echoServer(at: url, user: getuid() &+ 1)
    try server.start()
    defer { server.stop() }
    let answer = try exchange(RemoteRequest(arguments: ["toggle"]).line, at: url)
    #expect(answer.isEmpty)
}

@Test func aSocketLeftByADeadRunIsReplaced() throws {
    let url = try socketURL()
    // Bound and closed without being removed, as a crash leaves it.
    var address = try AgentSocket.address(of: url)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    close(fd)
    #expect(bound == 0)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(!AgentSocket.isListening(at: url))
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    #expect(try ask(["play"], at: url).ok)
}

@Test func aLiveSocketIsNeverReplaced() throws {
    let url = try socketURL()
    let first = echoServer(at: url)
    try first.start()
    defer { first.stop() }
    let second = echoServer(at: url)
    #expect(throws: RemoteCommandError.self) { try second.start() }
    #expect(try ask(["play"], at: url).ok)
}

@Test func somethingElseInTheWayIsLeftAlone() throws {
    let url = try socketURL()
    try Data("keep me".utf8).write(to: url)
    let server = echoServer(at: url)
    #expect(throws: RemoteCommandError.self) { try server.start() }
    #expect(try String(contentsOf: url, encoding: .utf8) == "keep me")
}

@Test func stoppingRemovesTheSocketAndClosesIt() throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    #expect(FileManager.default.fileExists(atPath: url.path))
    server.stop()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(!AgentSocket.isListening(at: url))
    // Stopping again, or starting again, is fine.
    server.stop()
    try server.start()
    defer { server.stop() }
    #expect(try ask(["play"], at: url).ok)
}

@Test func aRequestThatIsntOneIsRefusedWithAnError() throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    let response = try RemoteResponse.decode(try exchange(Data("hello\n".utf8), at: url).dropLast())
    #expect(!response.ok)
    #expect(response.code == 64)
    let old = try RemoteResponse.decode(try exchange(Data(#"{"v":99,"arguments":["now"]}"#.utf8 + [10]), at: url).dropLast())
    #expect(old.error?.contains("version") == true)
}

@Test func aRequestOverTheLimitIsRefused() throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    let long = Data(repeating: UInt8(ascii: "a"), count: AgentSocket.maximumRequest + 10) + [10]
    let response = try RemoteResponse.decode(try exchange(long, at: url).dropLast())
    #expect(!response.ok)
}

@Test func aClientThatHangsUpWithoutAskingGetsNothingAndDoesNoHarm() throws {
    let url = try socketURL()
    let server = echoServer(at: url)
    try server.start()
    defer { server.stop() }
    #expect(try exchange(Data(), at: url, closeWriting: true).isEmpty)
    #expect(try ask(["play"], at: url).ok)
}

@Test func aPathThatDoesntFitIsAnError() {
    let long = URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 200) + "/agent.sock")
    #expect(throws: RemoteCommandError.self) { try AgentSocket.address(of: long) }
}

@Test func theSocketLivesInTheAppsFolderByBundleIdentifier() throws {
    let release = try #require(RemoteSocketPath.url(bundleIdentifier: "dev.lorcan.Warble"))
    let dev = try #require(RemoteSocketPath.url(bundleIdentifier: "dev.lorcan.Warble.dev"))
    #expect(release != dev)
    #expect(release.lastPathComponent == "agent.sock")
    #expect(release.path.hasSuffix("/Application Support/dev.lorcan.Warble/agent.sock"))
}
