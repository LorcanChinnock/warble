import Foundation
import os
import Synchronization

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "now-playing")

/// Reads what's playing, and sends commands, through mediaremote-adapter, which `scripts/bundle.sh` puts in the app's
/// resources. Since macOS 15.4 only Apple-signed processes may read MediaRemote, so each command runs the adapter's
/// script under `/usr/bin/perl`, which loads the adapter's framework.
///
/// `start()` runs `stream` for as long as Warble does. It waits on MediaRemote rather than polling, so it costs nothing
/// while nothing changes. `watched(_:)` makes sure it ends with Warble, however Warble ends. When it exits on its own, `AdapterSupervisor` decides whether to check with `test` and start
/// it again, and when it gives up `states` ends, so Warble can switch to `ScriptSource`.
public final class AdapterSource: NowPlayingSource {
    public struct Paths: Sendable {
        public var script: URL
        public var framework: URL
        public var testClient: URL

        public init(script: URL, framework: URL, testClient: URL) {
            self.script = script
            self.framework = framework
            self.testClient = testClient
        }

        /// The adapter in `resources`, or `nil` when it isn't there, as in a build run outside the app bundle.
        public init?(resources: URL) {
            self.init(
                script: resources.appendingPathComponent("mediaremote-adapter.pl"),
                framework: resources.appendingPathComponent("MediaRemoteAdapter.framework"),
                testClient: resources.appendingPathComponent("MediaRemoteAdapterTestClient")
            )
            guard [script, framework, testClient].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                return nil
            }
        }
    }

    public let states: AsyncStream<PlaybackState?>
    private let continuation: AsyncStream<PlaybackState?>.Continuation
    private let paths: Paths
    private let runner = Mutex(Runner())

    /// Everything that changes, behind one lock: the readers, the exit handlers and `stop()` run on different threads.
    private struct Runner {
        var process: Process?
        var startedAt = Date.distantPast
        /// Bumped by each start and by `stop()`, so a handler for a process that has since been replaced does nothing.
        var generation = 0
        var stopped = false
        var supervisor = AdapterSupervisor()
        var stream = AdapterStream()
        /// The bytes after the last newline, which the next read finishes.
        var partialLine = Data()
    }

    public init(paths: Paths) {
        self.paths = paths
        (states, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Which backend the supervisor has settled on, which tells the Doctor why the adapter gave up.
    public var backend: AdapterSupervisor.Backend {
        runner.withLock { $0.supervisor.backend }
    }

    public func start() {
        runner.withLock { $0.stopped = false }
        startStream()
    }

    /// Ends the stream. Without this, a quit leaves the stream to its watchdog.
    public func stop() {
        let process = runner.withLock { runner in
            runner.stopped = true
            runner.generation += 1
            defer { runner.process = nil }
            return runner.process
        }
        process?.terminate()
    }

    public func send(_ command: PlaybackCommand) async {
        let status = await run(command.adapterArguments)
        if status != 0 {
            log.error("\(command.adapterArguments.joined(separator: " "), privacy: .public) exited \(status)")
        }
    }

    private func arguments(_ command: [String]) -> [String] {
        [paths.script.path, paths.framework.path, paths.testClient.path] + command
    }

    /// Runs `arguments` under `/usr/bin/perl` behind a watchdog, a forked Perl process that waits on stdin and stops the
    /// stream when stdin closes. Warble holds stdin's only write end and never writes, so the kernel closes it when
    /// Warble ends however it ends, a crash or `kill -9` included, and Warble closes it once the stream has exited, so the
    /// watchdog goes too. The stream itself never reads stdin, and without this it runs until its next write, which can
    /// be days when nothing plays. The stream execs in the process Warble started, so `terminate()` still reaches it.
    static func watched(_ arguments: [String]) -> [String] {
        let watchdog = """
            my $stream = $$;
            my $watchdog = fork;
            if (defined $watchdog && $watchdog == 0) {
                close STDOUT; close STDERR;
                1 while sysread(STDIN, my $byte, 1);
                kill 'TERM', $stream if getppid() == $stream;
                POSIX::_exit(0);
            }
            exec '/usr/bin/perl', @ARGV or exit 127;
            """
        return ["-MPOSIX", "-e", watchdog, "--"] + arguments
    }

    private func startStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = Self.watched(arguments(["stream", "--micros"]))
        let output = Pipe()
        process.standardOutput = output
        let lifeline = Pipe()
        process.standardInput = lifeline
        process.standardError = FileHandle.nullDevice
        let generation = runner.withLock { runner in
            runner.generation += 1
            runner.process = process
            runner.startedAt = .now
            runner.stream = AdapterStream()
            runner.partialLine = Data()
            return runner.generation
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.read(data, generation: generation)
            }
        }
        process.terminationHandler = { [weak self] process in
            try? lifeline.fileHandleForWriting.close()
            self?.streamExited(process, generation: generation)
        }
        do {
            try process.run()
            log.notice("Stream started")
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            try? lifeline.fileHandleForWriting.close()
            log.error("Stream didn't start: \(error.localizedDescription, privacy: .public)")
            streamExited(nil, generation: generation)
        }
    }

    /// Applies each whole line in `data`. Parsing, and decoding the artwork, happen here on the reader's thread rather
    /// than on the main actor.
    private func read(_ data: Data, generation: Int) {
        let changes: [PlaybackState?] = runner.withLock { runner in
            guard runner.generation == generation else { return [] }
            runner.partialLine.append(data)
            var changes: [PlaybackState?] = []
            while let newline = runner.partialLine.firstIndex(of: UInt8(ascii: "\n")) {
                let line = runner.partialLine[runner.partialLine.startIndex..<newline]
                runner.partialLine = Data(runner.partialLine[(newline + 1)...])
                do {
                    if try runner.stream.apply(Data(line), at: .now) {
                        changes.append(runner.stream.state)
                    }
                } catch {
                    log.error("Unreadable line from the stream: \(error.localizedDescription, privacy: .public)")
                }
            }
            return changes
        }
        // Only the newest matters, and the stream keeps only the newest anyway.
        if let latest = changes.last {
            continuation.yield(latest)
        }
    }

    private func streamExited(_ process: Process?, generation: Int) {
        let step: AdapterSupervisor.Step? = runner.withLock { runner in
            guard runner.generation == generation, !runner.stopped else { return nil }
            runner.process = nil
            return runner.supervisor.streamExited(afterRunning: Date.now.timeIntervalSince(runner.startedAt))
        }
        guard let step else { return }
        log.error("Stream exited with status \(process?.terminationStatus ?? -1)")
        continuation.yield(nil)
        perform(step)
    }

    private func perform(_ step: AdapterSupervisor.Step) {
        switch step {
        case .runTest(let delay):
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { await self?.test() }
            }
        case .startStream:
            guard !runner.withLock({ $0.stopped }) else { return }
            startStream()
        case .giveUp:
            log.fault("Gave up on the adapter until Warble is opened again")
            continuation.finish()
        }
    }

    private func test() async {
        guard !runner.withLock({ $0.stopped }) else { return }
        let status = await run(["test"])
        log.notice("Adapter test exited with status \(status)")
        perform(runner.withLock { $0.supervisor.testExited(status: status) })
    }

    /// Runs the adapter with `command` and returns its exit status, or -1 when it couldn't start.
    private func run(_ command: [String]) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = arguments(command)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                log.error("Adapter didn't start: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: -1)
            }
        }
    }
}
