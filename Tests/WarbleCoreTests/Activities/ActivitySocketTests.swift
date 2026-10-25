import Darwin
import Foundation
import Testing
import WarbleModel
@testable import WarbleCore

/// A short folder of its own, since a socket's whole path must fit in 103 bytes.
private func socketURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("act-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("activities.sock")
}

private let startLine = #"{"v":1,"op":"start","id":"a","title":"Hello","from":"Test"}"#
private let endLine = #"{"v":1,"op":"end","id":"a"}"#

/// What the socket did on the main actor: the actions it dispatched, in order.
@MainActor
private final class Harness {
    var actions: [AppAction] = []
    var state = AppState(showsActivities: true)
    let handler: ActivityHandler
    let socket: ActivitySocket
    let url: URL

    init(user: uid_t = getuid(), partialLineTimeout: Duration = .seconds(5)) throws {
        url = try socketURL()
        var dispatched: ((AppAction) -> Void)?
        handler = ActivityHandler(state: { AppState(showsActivities: true) }, dispatch: { dispatched?($0) }, clock: FixedClock())
        socket = ActivitySocket(url: url, user: user, partialLineTimeout: partialLineTimeout) { _, client in
            ActivitySender(client: client, identifier: "/bin/test", name: "test")
        }
        dispatched = { [unowned self] in actions.append($0) }
    }
}

private struct FixedClock: WallClock {
    var now: Date { Date(timeIntervalSince1970: 1_000_000) }
}

/// A plain client, as an app or `nc -U` would be.
private final class Client: @unchecked Sendable {
    let fd: Int32

    init(_ url: URL) throws {
        var address = try UnixSocket.address(of: url)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw RemoteCommandError.unavailable("not connected: \(String(cString: strerror(errno)))") }
        UnixSocket.setTimeout(fd, SO_RCVTIMEO, .seconds(2))
        UnixSocket.keepSignalsOff(fd)
    }

    deinit { close(fd) }

    func send(_ text: String) {
        let bytes = Data(text.utf8)
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// The next line, or `nil` at the end of the connection or after the timeout. The read blocks, so it's off the main
    /// actor, which the socket needs to answer.
    func line() async -> String? {
        await Task.detached { [fd] in
            var data = Data()
            var byte: UInt8 = 0
            while read(fd, &byte, 1) == 1 {
                if byte == UInt8(ascii: "\n") { return String(decoding: data, as: UTF8.self) }
                data.append(byte)
            }
            return nil
        }.value
    }
}

/// Lets the main actor run what the socket queued on it, until `condition` holds.
@MainActor
private func wait(until condition: () -> Bool) async {
    for _ in 0 ..< 500 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor @Test func aLineGetsItsReplyAndTheConnectionStays() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(startLine + "\n")
    #expect((await client.line()) == #"{"ok":true,"re":"start","v":1}"#)
    client.send(endLine + "\n")
    #expect((await client.line()) == #"{"ok":true,"re":"end","v":1}"#)
    #expect(harness.actions.count == 2)
}

@MainActor @Test func twoLinesInOneReadAreBothAnsweredInOrder() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(startLine + "\n" + endLine + "\n")
    #expect((await client.line())?.contains(#""re":"start""#) == true)
    #expect((await client.line())?.contains(#""re":"end""#) == true)
}

@MainActor @Test func aLineArrivingInPiecesIsOneLine() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(String(startLine.prefix(20)))
    try await Task.sleep(for: .milliseconds(50))
    client.send(String(startLine.dropFirst(20)) + "\n" + String(endLine.prefix(5)))
    #expect((await client.line())?.contains(#""ok":true"#) == true)
    // The start of the next line is kept, not dropped with the first.
    client.send(String(endLine.dropFirst(5)) + "\n")
    #expect((await client.line())?.contains(#""re":"end""#) == true)
}

@MainActor @Test func aQuietConnectionIsNeverClosedForIt() async throws {
    let harness = try Harness(partialLineTimeout: .milliseconds(100))
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    try await Task.sleep(for: .milliseconds(400))
    client.send(startLine + "\n")
    #expect((await client.line())?.contains(#""ok":true"#) == true)
}

@MainActor @Test func aHalfLineThatNeverFinishesIsRefusedAndClosed() async throws {
    let harness = try Harness(partialLineTimeout: .milliseconds(100))
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(#"{"v":1,"op":"st"#)
    #expect((await client.line())?.contains("took more than") == true)
    #expect((await client.line()) == nil)
}

@MainActor @Test func aLineOverTheLimitIsRefusedByTheHandlerWithoutClosing() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(String(repeating: "a", count: ActivityLimits.lineBytes + 50) + "\n")
    #expect((await client.line())?.contains(#""ok":false"#) == true)
    client.send(startLine + "\n")
    #expect((await client.line())?.contains(#""ok":true"#) == true)
}

@MainActor @Test func aLongLineWithNoEndIsRefusedAndClosed() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(String(repeating: "a", count: ActivityLimits.lineBytes + 50))
    #expect((await client.line())?.contains("without an end") == true)
    #expect((await client.line()) == nil)
}

@MainActor @Test func closingAConnectionEndsWhatItStarted() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    var client: Client? = try Client(harness.url)
    client?.send(startLine + "\n")
    _ = await client?.line()
    client = nil
    await wait { harness.actions.contains(.activityClientClosed(client: 1)) }
    #expect(harness.actions.contains(.activityClientClosed(client: 1)))
}

@MainActor @Test func eachConnectionGetsItsOwnNumber() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let first = try Client(harness.url)
    let second = try Client(harness.url)
    first.send(startLine + "\n")
    second.send(startLine + "\n")
    _ = await first.line()
    _ = await second.line()
    let clients = harness.actions.compactMap { action -> Int? in
        if case .activityStarted(let activity) = action { activity.key.client } else { nil }
    }
    #expect(Set(clients) == [1, 2])
}

@MainActor @Test func aSendReachesOnlyItsConnection() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let first = try Client(harness.url)
    let second = try Client(harness.url)
    first.send(startLine + "\n")
    second.send(startLine + "\n")
    _ = await first.line()
    _ = await second.line()
    harness.socket.send(ActivityEvent.button("stop").line(id: "a"), to: 2)
    #expect((await second.line()) == #"{"button":"stop","event":"button","id":"a","v":1}"#)
    harness.socket.send(ActivityEvent.ended(.expired).line(id: "a"), to: 1)
    #expect((await first.line())?.contains(#""reason":"expired""#) == true)
}

@MainActor @Test func aSendToAClosedConnectionIsDropped() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    var client: Client? = try Client(harness.url)
    client?.send(startLine + "\n")
    _ = await client?.line()
    client = nil
    await wait { harness.actions.contains(.activityClientClosed(client: 1)) }
    harness.socket.send(ActivityEvent.button("stop").line(id: "a"), to: 1)
    harness.socket.send(ActivityEvent.button("stop").line(id: "a"), to: 99)
}

@MainActor @Test func theSocketIsPrivateAndTheFolderToo() throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let mode = try #require(FileManager.default.attributesOfItem(atPath: harness.url.path)[.posixPermissions] as? Int)
    #expect(mode == 0o600)
    let folder = try #require(FileManager.default.attributesOfItem(atPath: harness.url.deletingLastPathComponent().path)[.posixPermissions] as? Int)
    #expect(folder == 0o700)
}

@MainActor @Test func anotherUsersConnectionIsClosedUnanswered() async throws {
    let harness = try Harness(user: getuid() &+ 1)
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let client = try Client(harness.url)
    client.send(startLine + "\n")
    #expect((await client.line()) == nil)
    #expect(harness.actions.isEmpty)
}

@MainActor @Test func stoppingClosesEveryConnectionAndRemovesTheSocket() async throws {
    let harness = try Harness()
    try harness.socket.start(handler: harness.handler)
    let client = try Client(harness.url)
    client.send(startLine + "\n")
    _ = await client.line()
    harness.socket.stop()
    #expect(!FileManager.default.fileExists(atPath: harness.url.path))
    #expect(!harness.socket.isListening)
    #expect((await client.line()) == nil)
    await wait { harness.actions.contains(.activityClientClosed(client: 1)) }
    #expect(harness.actions.contains(.activityClientClosed(client: 1)))
    // Stopping again, or starting again, is fine.
    harness.socket.stop()
    try harness.socket.start(handler: harness.handler)
    defer { harness.socket.stop() }
    let again = try Client(harness.url)
    again.send(startLine + "\n")
    #expect((await again.line())?.contains(#""ok":true"#) == true)
}

@MainActor @Test func aLiveSocketIsNeverReplacedButADeadOneIs() throws {
    let first = try Harness()
    try first.socket.start(handler: first.handler)
    defer { first.socket.stop() }
    let second = ActivitySocket(url: first.url)
    #expect(throws: RemoteCommandError.self) { try second.start(handler: first.handler) }
    #expect(first.socket.isListening)
    // Bound and closed without being removed, as a crash leaves it.
    let url = try socketURL()
    var address = try UnixSocket.address(of: url)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    _ = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    close(fd)
    let replacing = ActivitySocket(url: url)
    try replacing.start(handler: first.handler)
    replacing.stop()
}

@Test func theActivitiesSocketIsNextToTheCommandLinesOne() throws {
    let agent = try #require(RemoteSocketPath.url(bundleIdentifier: "dev.lorcan.Warble"))
    let activities = try #require(RemoteSocketPath.activitiesURL(bundleIdentifier: "dev.lorcan.Warble"))
    #expect(activities.lastPathComponent == "activities.sock")
    #expect(activities.deletingLastPathComponent() == agent.deletingLastPathComponent())
}

@MainActor @Test func aSocketLeftByAKilledRunIsRemovedButALiveOneIsNot() throws {
    let url = try socketURL()
    var address = try UnixSocket.address(of: url)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    _ = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    close(fd)
    #expect(FileManager.default.fileExists(atPath: url.path))
    ActivitySocket(url: url).removeLeftover()
    #expect(!FileManager.default.fileExists(atPath: url.path))

    let live = try Harness()
    try live.socket.start(handler: live.handler)
    defer { live.socket.stop() }
    ActivitySocket(url: live.url).removeLeftover()
    #expect(FileManager.default.fileExists(atPath: live.url.path))
}
