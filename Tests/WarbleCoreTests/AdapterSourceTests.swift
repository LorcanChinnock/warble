import Foundation
import Testing
import WarbleCore

/// A stand-in for mediaremote-adapter.pl: it logs each command to `log`, and for `stream` runs `stream`, Perl that
/// prints to STDOUT. `test` exits with `testStatus`.
private struct FakeAdapter {
    let folder: URL
    let paths: AdapterSource.Paths
    var log: URL { folder.appendingPathComponent("log") }

    init(stream: String, testStatus: Int32 = 0) throws {
        folder = try temporaryFolder()
        let script = folder.appendingPathComponent("adapter.pl")
        try """
        $| = 1;
        my ($framework, $client, $command, @rest) = @ARGV;
        open(my $log, '>>', '\(folder.path)/log'); print $log join(' ', $command, @rest), "\\n"; close($log);
        if ($command eq 'test') { exit \(testStatus); }
        if ($command eq 'stream') { \(stream) }
        exit 0;
        """.write(to: script, atomically: true, encoding: .utf8)
        paths = AdapterSource.Paths(
            script: script,
            framework: folder.appendingPathComponent("framework"),
            testClient: folder.appendingPathComponent("client")
        )
    }

    func commands() throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// The first `count` states `source` reports, or fewer if `timeout` passes first.
private func states(_ source: AdapterSource, count: Int, timeout: Duration = .seconds(10)) async -> [PlaybackState?] {
    await withTaskGroup(of: [PlaybackState?].self) { group in
        group.addTask {
            var states: [PlaybackState?] = []
            for await state in source.states {
                states.append(state)
                if states.count == count { break }
            }
            return states
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return []
        }
        let first = await group.next() ?? []
        group.cancelAll()
        return first
    }
}

@Test func theSourceReadsLinesThatArriveInPieces() async throws {
    // The second line is printed in two writes, as a long line with artwork can be.
    let adapter = try FakeAdapter(stream: #"""
    print '{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","title":"Song","playing":true}}', "\n";
    select(undef, undef, undef, 0.2);
    print '{"type":"data","diff":true,"payload":{"artist":';
    select(undef, undef, undef, 0.2);
    print '"Artist"}}', "\n";
    sleep 30;
    """#)
    defer { adapter.remove() }
    let source = AdapterSource(paths: adapter.paths)
    source.start()
    defer { source.stop() }
    let seen = await states(source, count: 2)
    #expect(seen.map { $0?.title } == ["Song", "Song"])
    #expect(seen.last??.artist == "Artist")
    #expect(try adapter.commands() == ["stream --micros"])
}

@Test func commandsRunTheAdapterWithTheirArguments() async throws {
    let adapter = try FakeAdapter(stream: "")
    defer { adapter.remove() }
    let source = AdapterSource(paths: adapter.paths)
    await source.send(.togglePlayPause)
    await source.send(.seek(to: 1.5))
    #expect(try adapter.commands() == ["send 2", "seek 1500000"])
}

@Test func aStreamThatExitsIsTestedAndStartedAgain() async throws {
    let adapter = try FakeAdapter(stream: #"""
    print '{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","title":"Song","playing":true}}', "\n";
    select(undef, undef, undef, 0.2);
    exit 1;
    """#)
    defer { adapter.remove() }
    let source = AdapterSource(paths: adapter.paths)
    source.start()
    defer { source.stop() }
    // The track, nothing once the stream exits, then the track again from the restarted stream.
    let seen = await states(source, count: 3)
    #expect(seen.map { $0?.title } == ["Song", nil, "Song"])
    #expect(try adapter.commands().prefix(3) == ["stream --micros", "test", "stream --micros"])
}

@Test func aStreamIsNotStartedAgainWhenTheTestFails() async throws {
    let adapter = try FakeAdapter(stream: "exit 1;", testStatus: 1)
    defer { adapter.remove() }
    let source = AdapterSource(paths: adapter.paths)
    source.start()
    defer { source.stop() }
    _ = await states(source, count: 1)
    // Long enough for a restart, had there been one.
    try await Task.sleep(for: .seconds(AdapterSupervisor.restartDelays[0] + 1))
    #expect(try adapter.commands() == ["stream --micros", "test"])
}

@Test func theStatesEndWhenTheAdapterGivesUp() async throws {
    let adapter = try FakeAdapter(stream: "exit 1;", testStatus: 1)
    defer { adapter.remove() }
    let source = AdapterSource(paths: adapter.paths)
    source.start()
    defer { source.stop() }
    // Nothing once the stream exits, then the end, well before the timeout's empty list.
    #expect(await states(source, count: 2) == [nil])
}

@Test func theAdapterIsFoundInTheAppsResources() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(AdapterSource.Paths(resources: folder) == nil)
    for name in ["mediaremote-adapter.pl", "MediaRemoteAdapter.framework", "MediaRemoteAdapterTestClient"] {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
    }
    let paths = try #require(AdapterSource.Paths(resources: folder))
    #expect(paths.script.lastPathComponent == "mediaremote-adapter.pl")
}
