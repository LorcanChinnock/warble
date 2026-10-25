import Darwin
import Foundation

/// The Unix socket the running app answers the `warble` command on. One `RemoteRequest` line per connection, then one
/// `RemoteResponse` line, then the connection closes. Only the same user can connect: the folder is 0700, the socket
/// 0600, and each peer is checked too.
public enum AgentSocket {
    /// The longest request the server reads. Anything longer is refused.
    public static let maximumRequest = 64 * 1024
    /// How long the server waits for a client to send its request.
    static let requestTimeout = Duration.seconds(5)

    /// Accepts connections on a queue of its own, and hands each request to `handler`. It's opened while the Developer card
    /// has the command line on and closed when it's turned off, so while it's off no socket exists.
    public final class Server: @unchecked Sendable {
        public typealias Handler = @Sendable (RemoteRequest) async -> RemoteResponse

        public let url: URL
        /// The only user whose connections are answered: this one, but for tests of the check.
        let user: uid_t
        private let handler: Handler
        private let queue = DispatchQueue(label: "dev.lorcan.Warble.agent-socket")
        /// Read and written on `queue` only.
        private var source: DispatchSourceRead?

        public convenience init(url: URL, handler: @escaping Handler) {
            self.init(url: url, user: getuid(), handler: handler)
        }

        init(url: URL, user: uid_t, handler: @escaping Handler) {
            self.url = url
            self.user = user
            self.handler = handler
        }

        /// Makes the folder and the socket and starts listening. A socket left by a run that died is replaced, but one
        /// another process still answers on is left alone, as `.unavailable`.
        public func start() throws(RemoteCommandError) {
            let fd = try UnixSocket.listen(at: url, purpose: "the command line")
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptAll(on: fd)
            }
            source.setCancelHandler {
                close(fd)
            }
            queue.sync {
                self.source?.cancel()
                self.source = source
            }
            source.resume()
        }

        /// Stops listening and removes the socket. Requests already being answered still get their answer.
        public func stop() {
            let wasListening = queue.sync {
                let listening = source != nil
                source?.cancel()
                source = nil
                return listening
            }
            if wasListening {
                unlink(url.path)
            }
        }

        private func acceptAll(on fd: Int32) {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    return
                }
                // Accepted sockets inherit the listener's O_NONBLOCK, but this one is read with a timeout instead.
                _ = fcntl(client, F_SETFL, 0)
                _ = fcntl(client, F_SETFD, FD_CLOEXEC)
                UnixSocket.keepSignalsOff(client)
                guard UnixSocket.peerUser(of: client) == user else {
                    close(client)
                    continue
                }
                let handler = handler
                // A thread of its own for the blocking read, since the global queues' threads can all be busy.
                Thread.detachNewThread {
                    Self.serve(client, handler: handler)
                }
            }
        }

        /// Reads one request from `client`, answers it, and closes it. Blocks only for the read.
        private static func serve(_ client: Int32, handler: @escaping Handler) {
            UnixSocket.setTimeout(client, SO_RCVTIMEO, AgentSocket.requestTimeout)
            UnixSocket.setTimeout(client, SO_SNDTIMEO, AgentSocket.requestTimeout)
            let request: RemoteRequest
            switch AgentSocket.readLine(client, limit: AgentSocket.maximumRequest, deadline: .now + AgentSocket.requestTimeout) {
            case .line(let data):
                do {
                    request = try RemoteRequest.decode(data)
                } catch {
                    AgentSocket.reply(.failure(error), to: client)
                    return
                }
            case .tooLong:
                AgentSocket.reply(.failure(.usage(nil, "the request is over \(AgentSocket.maximumRequest / 1024) KB")), to: client)
                return
            case .closed, .timedOut, .failed:
                close(client)
                return
            }
            // On a queue of its own: a serial queue, unlike the shared pool, gets a thread even when all of the pool's are
            // busy, so an answer never waits for work that holds every one of those, such as tests that block on it.
            let queue = DispatchQueue(label: "dev.lorcan.Warble.agent-socket.answer")
            Task(executorPreference: QueueExecutor(queue)) {
                AgentSocket.reply(await handler(request), to: client)
            }
        }
    }

    /// Runs tasks' jobs on a queue rather than the threads of the shared pool.
    final class QueueExecutor: TaskExecutor {
        private let queue: DispatchQueue

        init(_ queue: DispatchQueue) {
            self.queue = queue
        }

        func enqueue(_ job: consuming ExecutorJob) {
            let job = UnownedJob(job)
            queue.async {
                job.runSynchronously(on: self.asUnownedTaskExecutor())
            }
        }
    }

    /// Whether something answers at `url`.
    public static func isListening(at url: URL) -> Bool {
        UnixSocket.isListening(at: url)
    }

    static func address(of url: URL) throws(RemoteCommandError) -> sockaddr_un {
        try UnixSocket.address(of: url)
    }

    private static func reply(_ response: RemoteResponse, to client: Int32) {
        _ = UnixSocket.write(response.line, to: client)
        close(client)
    }

    enum ReadResult {
        case line(Data)
        case tooLong, closed, timedOut, failed
    }

    /// Reads up to the first newline, giving up past `limit` bytes or at `deadline`.
    static func readLine(_ fd: Int32, limit: Int, deadline: ContinuousClock.Instant) -> ReadResult {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = deadline - .now
            guard remaining > .zero else {
                return .timedOut
            }
            UnixSocket.setTimeout(fd, SO_RCVTIMEO, remaining)
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                return errno == EAGAIN || errno == EWOULDBLOCK ? .timedOut : .failed
            }
            if count == 0 {
                return .closed
            }
            if let newline = chunk[..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: chunk[..<newline])
                return data.count <= limit ? .line(data) : .tooLong
            }
            data.append(contentsOf: chunk[..<count])
            if data.count > limit {
                return .tooLong
            }
        }
    }

    static func setTimeout(_ fd: Int32, _ option: Int32, _ duration: Duration) {
        UnixSocket.setTimeout(fd, option, duration)
    }

    static func keepSignalsOff(_ fd: Int32) {
        UnixSocket.keepSignalsOff(fd)
    }
}
