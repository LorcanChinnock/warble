import Darwin
import Foundation
import WarbleModel

/// The Unix socket other apps show activities in the notch over, `activities.sock` next to the command line's. Unlike
/// `AgentSocket`, a connection stays open for as long as its sender has an activity, with one line in and one reply out, in
/// order, and button presses and endings sent back on it. A closed connection ends what it started.
///
/// It's open only while Settings › Activities is on. Only the same user can connect, and each connection is identified once,
/// when it connects (`ActivityPeer`). Everything is handled on the main actor, where the store runs, so a line shows in the
/// notch as soon as it's read.
@MainActor
public final class ActivitySocket: ActivityChannel {
    /// Works out who connected from the connected socket and the number it was given, off the main actor.
    typealias Identify = @Sendable (_ fd: Int32, _ client: Int) -> ActivitySender

    /// How long a line may take to arrive once its first byte has. A connection has no idle timeout, since an app that has
    /// nothing to say for hours is the normal case.
    public static let partialLineTimeout = Duration.seconds(5)

    public let url: URL
    private let user: uid_t
    private let partialLineTimeout: Duration
    private let identify: Identify
    private let queue = DispatchQueue(label: "dev.lorcan.Warble.activity-socket")
    private var listener: Listener?
    private var handler: ActivityHandler?
    private var connections: [Int: Connection] = [:]

    public convenience init(url: URL) {
        self.init(url: url, user: getuid(), partialLineTimeout: Self.partialLineTimeout, identify: ActivityPeer.identify)
    }

    init(url: URL, user: uid_t, partialLineTimeout: Duration, identify: @escaping Identify) {
        self.url = url
        self.user = user
        self.partialLineTimeout = partialLineTimeout
        self.identify = identify
    }

    public var isListening: Bool { listener != nil }

    /// Makes the folder and the socket and starts answering lines with `handler`. A socket left by a run that died is
    /// replaced, but one another process still answers on is left alone, as `.unavailable`.
    public func start(handler: ActivityHandler) throws(RemoteCommandError) {
        self.handler = handler
        guard listener == nil else { return }
        let fd = try UnixSocket.listen(at: url, purpose: "activities")
        let listener = Listener(fd: fd, owner: self, queue: queue, user: user, partialLineTimeout: partialLineTimeout, identify: identify)
        self.listener = listener
        listener.resume()
    }

    /// Removes a socket a run that was killed left behind, so with the setting off no `activities.sock` exists. One that
    /// something still answers on, or a file that isn't a socket, is left alone.
    public func removeLeftover() {
        guard listener == nil else { return }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, !UnixSocket.isListening(at: url) else { return }
        unlink(url.path)
    }

    /// Stops listening, removes the socket and closes every connection, which each sender sees as the end of its activities.
    public func stop() {
        guard let listener else { return }
        self.listener = nil
        listener.cancel()
        unlink(url.path)
        for connection in connections.values {
            connection.close()
        }
    }

    public func send(_ line: Data, to client: Int) {
        guard let connection = connections[client] else { return }
        if !connection.write(line) {
            connection.close()
        }
    }

    private func register(_ connection: Connection) -> Bool {
        guard listener != nil else { return false }
        connections[connection.sender.client] = connection
        return true
    }

    /// Lines arrive in the order they were read, since each read hops to the main queue in turn.
    private func received(_ lines: [Data], from connection: Connection) {
        guard let handler, connections[connection.sender.client] === connection else { return }
        for line in lines where !line.isEmpty {
            guard connection.write(handler.handle(line, from: connection.sender).line) else {
                connection.close()
                return
            }
        }
    }

    /// Tells the sender why, then hangs up: what it sent can't be read as lines any more.
    private func refuse(_ message: String, on connection: Connection) {
        guard connections[connection.sender.client] === connection else { return }
        _ = connection.write(ActivityReply.failure(ActivityError(message)).line)
        connection.close()
    }

    private func closed(_ connection: Connection) {
        guard connections[connection.sender.client] === connection else { return }
        connections[connection.sender.client] = nil
        handler?.closed(client: connection.sender.client)
    }

    /// Accepts connections on `queue`, and hands each to its sender's identification before it's read.
    private final class Listener: @unchecked Sendable {
        private let fd: Int32
        private let source: DispatchSourceRead
        private let queue: DispatchQueue
        private let user: uid_t
        private let partialLineTimeout: Duration
        private let identify: Identify
        private weak var owner: ActivitySocket?
        /// Read and written on `queue` only.
        private var lastClient = 0

        init(fd: Int32, owner: ActivitySocket, queue: DispatchQueue, user: uid_t, partialLineTimeout: Duration, identify: @escaping Identify) {
            self.fd = fd
            self.owner = owner
            self.queue = queue
            self.user = user
            self.partialLineTimeout = partialLineTimeout
            self.identify = identify
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        }

        func resume() {
            source.setEventHandler { [self] in acceptAll() }
            let fd = fd
            source.setCancelHandler { close(fd) }
            source.resume()
        }

        func cancel() {
            source.cancel()
        }

        private func acceptAll() {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                _ = fcntl(client, F_SETFL, O_NONBLOCK)
                _ = fcntl(client, F_SETFD, FD_CLOEXEC)
                UnixSocket.keepSignalsOff(client)
                guard UnixSocket.peerUser(of: client) == user else {
                    close(client)
                    continue
                }
                lastClient += 1
                let number = lastClient
                let identify = identify
                let queue = queue
                let timeout = partialLineTimeout
                // Checking a code signature can take a moment, so not on `queue`, which reads every other connection.
                DispatchQueue.global(qos: .userInitiated).async { [weak owner] in
                    let sender = identify(client, number)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            let connection = Connection(fd: client, sender: sender, owner: owner, queue: queue, partialLineTimeout: timeout)
                            guard let owner, owner.register(connection) else {
                                close(client)
                                return
                            }
                            connection.start()
                        }
                    }
                }
            }
        }
    }

    /// One sender's connection. `buffer` and the timer are used on `queue` only, and `isOpen` is guarded by `lock`.
    private final class Connection: @unchecked Sendable {
        let sender: ActivitySender
        private let fd: Int32
        private let queue: DispatchQueue
        private let partialLineTimeout: Duration
        private weak var owner: ActivitySocket?
        private var source: DispatchSourceRead?
        private let lock = NSLock()
        private var isOpen = true
        private var buffer = Data()
        private var timeout: DispatchWorkItem?

        init(fd: Int32, sender: ActivitySender, owner: ActivitySocket?, queue: DispatchQueue, partialLineTimeout: Duration) {
            self.fd = fd
            self.sender = sender
            self.owner = owner
            self.queue = queue
            self.partialLineTimeout = partialLineTimeout
        }

        func start() {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            self.source = source
            source.setEventHandler { [self] in readable() }
            source.setCancelHandler { [self] in
                lock.lock()
                isOpen = false
                Darwin.close(fd)
                lock.unlock()
                timeout?.cancel()
                timeout = nil
                // Breaks the cycle between the source and its handler.
                self.source = nil
                DispatchQueue.main.async { [weak owner, self] in
                    MainActor.assumeIsolated { owner?.closed(self) }
                }
            }
            source.resume()
        }

        /// Closes the connection once. What it started ends when the main actor hears of it.
        func close() {
            source?.cancel()
        }

        /// Writes all of `data` without waiting. False if the connection is closed or its sender isn't reading, in which
        /// case it's as good as closed.
        func write(_ data: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard isOpen else { return false }
            return data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        return false
                    }
                    offset += written
                }
                return true
            }
        }

        /// Reads what has arrived and hands the lines in it to the main actor, keeping the bytes after the last newline for
        /// the next read.
        private func readable() {
            var chunk = [UInt8](repeating: 0, count: 8192)
            let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR { source?.cancel() }
                return
            }
            if count == 0 {
                source?.cancel()
                return
            }
            buffer.append(contentsOf: chunk[..<count])
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(Data(buffer[buffer.startIndex ..< newline]))
                buffer.removeSubrange(buffer.startIndex ... newline)
            }
            let started = !lines.isEmpty
            if started {
                let batch = lines
                DispatchQueue.main.async { [weak owner, self] in
                    MainActor.assumeIsolated { owner?.received(batch, from: self) }
                }
            }
            if buffer.count > ActivityLimits.lineBytes {
                refuse("the line is over \(ActivityLimits.lineBytes) bytes without an end")
            } else if buffer.isEmpty {
                timeout?.cancel()
                timeout = nil
            } else if started || timeout == nil {
                // A new partial line has started, so it's the one the bound counts.
                timeout?.cancel()
                let item = DispatchWorkItem { [self] in
                    refuse("a line took more than \(partialLineTimeout.components.seconds) seconds to arrive")
                }
                timeout = item
                queue.asyncAfter(deadline: .now() + .nanoseconds(Int(partialLineTimeout / .nanoseconds(1))), execute: item)
            }
        }

        private func refuse(_ message: String) {
            DispatchQueue.main.async { [weak owner, self] in
                MainActor.assumeIsolated { owner?.refuse(message, on: self) }
            }
        }
    }
}
