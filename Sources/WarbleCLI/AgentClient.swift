import Darwin
import Foundation
import WarbleModel

/// The command's half of the app's socket: connects, sends one request line and reads the one answer line. It's here and
/// not in WarbleCore because the command depends on WarbleModel only, which keeps it small and quick to start.
enum AgentClient {
    /// How long to wait for the app to answer. Every command answers at once, so a longer wait means the app is stuck.
    static let timeout = 10.0

    /// Sends `request` to the app listening at `url` and returns its answer's line, without the newline.
    static func exchange(_ request: Data, at url: URL) throws(RemoteCommandError) -> Data {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(url.path.utf8)
        guard path.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw .cantCreate("the socket's path, \(url.path), is too long for a socket")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw .io("couldn't make a socket: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            throw .unavailable(RemoteSocketPath.nothingAnswering)
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        // A write the app cut short, because the request was too long, still leaves its answer to read.
        _ = request.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var answer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw .unavailable("Warble didn't answer within \(Int(timeout)) seconds. Check that it isn't waiting on a dialog, then try again.")
                }
                throw .io("reading Warble's answer failed: \(String(cString: strerror(errno)))")
            }
            if count == 0 {
                throw .io("Warble closed the connection without a usable answer")
            }
            if let newline = chunk[..<count].firstIndex(of: UInt8(ascii: "\n")) {
                answer.append(contentsOf: chunk[..<newline])
                return answer
            }
            answer.append(contentsOf: chunk[..<count])
            if answer.count > 1_000_000 {
                throw .io("Warble's answer is too long")
            }
        }
    }
}
