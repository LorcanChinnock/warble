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
            var address = try AgentSocket.address(of: url)
            let folder = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Set every time, so a folder made looser by hand is closed again.
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            } catch {
                throw .cantCreate("couldn't make \(folder.path): \(error.localizedDescription)")
            }
            var info = stat()
            if lstat(url.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFSOCK else {
                    throw .cantCreate("\(url.path) is in the way and isn't a socket")
                }
                guard !AgentSocket.isListening(at: url) else {
                    throw .unavailable("another copy of Warble is already answering the command line at \(url.path)")
                }
                unlink(url.path)
            }
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw .io("couldn't make a socket: \(AgentSocket.reason())")
            }
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            // A socket made with the process's umask could be open to others for a moment, so the file is made private
            // by the folder (0700) and then closed down to 0600.
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, chmod(url.path, 0o600) == 0, listen(fd, 16) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                let reason = AgentSocket.reason()
                close(fd)
                unlink(url.path)
                throw .cantCreate("couldn't listen at \(url.path): \(reason)")
            }
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
                AgentSocket.keepSignalsOff(client)
                guard AgentSocket.peerUser(of: client) == user else {
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
            AgentSocket.setTimeout(client, SO_RCVTIMEO, AgentSocket.requestTimeout)
            AgentSocket.setTimeout(client, SO_SNDTIMEO, AgentSocket.requestTimeout)
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
            Task {
                AgentSocket.reply(await handler(request), to: client)
            }
        }
    }

    /// Whether something answers at `url`.
    public static func isListening(at url: URL) -> Bool {
        guard let fd = try? connect(to: url) else {
            return false
        }
        close(fd)
        return true
    }

    private static func connect(to url: URL) throws(RemoteCommandError) -> Int32 {
        var address = try address(of: url)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw .io("couldn't make a socket: \(reason())")
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw .unavailable(RemoteSocketPath.nothingAnswering)
        }
        return fd
    }

    /// The `sockaddr_un` for `url`, whose path must fit in `sun_path`, ending zero included.
    static func address(of url: URL) throws(RemoteCommandError) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(url.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.count < capacity else {
            throw .cantCreate("the socket's path, \(url.path), is \(path.count) bytes; a socket's path can be at most \(capacity - 1)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        return address
    }

    private static func reply(_ response: RemoteResponse, to client: Int32) {
        _ = write(response.line, to: client)
        close(client)
    }

    /// Writes all of `data`. False if the other end went away or stopped reading.
    private static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
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
            setTimeout(fd, SO_RCVTIMEO, remaining)
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

    /// Sets a send or receive timeout of at least a millisecond, since zero would mean none.
    static func setTimeout(_ fd: Int32, _ option: Int32, _ duration: Duration) {
        let (seconds, attoseconds) = max(duration, .milliseconds(1)).components
        var value = timeval(tv_sec: Int(seconds), tv_usec: suseconds_t(attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func reason() -> String {
        String(cString: strerror(errno))
    }

    /// Stops writes to `fd` raising `SIGPIPE` when its peer goes away, which would end the process.
    static func keepSignalsOff(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// The user at the other end of the connected socket `fd`, which the server checks is this one. `nil` when it can't tell.
    static func peerUser(of fd: Int32) -> uid_t? {
        var uid = uid_t()
        var gid = gid_t()
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
    }
}
