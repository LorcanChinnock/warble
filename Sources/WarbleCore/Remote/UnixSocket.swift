import Darwin
import Foundation

/// The parts of a Unix socket that `AgentSocket` (the command line) and `ActivitySocket` (other apps' activities) share:
/// making a private listening socket, and the small calls around a connected one.
enum UnixSocket {
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

    /// Makes the folder (0700) and a listening, non-blocking socket at `url` (0600), and returns its descriptor. A socket left
    /// by a run that died is replaced, but one another process still answers on is left alone, as `.unavailable`. `purpose`
    /// finishes "another copy of Warble is already answering …" in that error.
    static func listen(at url: URL, purpose: String) throws(RemoteCommandError) -> Int32 {
        var address = try address(of: url)
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
            guard !isListening(at: url) else {
                throw .unavailable("another copy of Warble is already answering \(purpose) at \(url.path)")
            }
            unlink(url.path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw .io("couldn't make a socket: \(reason())")
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        // A socket made with the process's umask could be open to others for a moment, so the file is made private
        // by the folder (0700) and then closed down to 0600.
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(url.path, 0o600) == 0, Darwin.listen(fd, 16) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let reason = reason()
            close(fd)
            unlink(url.path)
            throw .cantCreate("couldn't listen at \(url.path): \(reason)")
        }
        return fd
    }

    /// Whether something answers at `url`.
    static func isListening(at url: URL) -> Bool {
        guard let fd = try? connect(to: url) else {
            return false
        }
        close(fd)
        return true
    }

    /// A connected socket to `url`.
    static func connect(to url: URL) throws(RemoteCommandError) -> Int32 {
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
        keepSignalsOff(fd)
        return fd
    }

    /// Writes all of `data`. False if the other end went away or stopped reading.
    static func write(_ data: Data, to fd: Int32) -> Bool {
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

    /// Sets a send or receive timeout of at least a millisecond, since zero would mean none.
    static func setTimeout(_ fd: Int32, _ option: Int32, _ duration: Duration) {
        let (seconds, attoseconds) = max(duration, .milliseconds(1)).components
        var value = timeval(tv_sec: Int(seconds), tv_usec: suseconds_t(attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    static func reason() -> String {
        String(cString: strerror(errno))
    }

    /// Stops writes to `fd` raising `SIGPIPE` when its peer goes away, which would end the process.
    /// `SO_NOSIGPIPE` can't be set on a socket whose peer has already gone, so the signal is ignored as well.
    static func keepSignalsOff(_ fd: Int32) {
        signal(SIGPIPE, SIG_IGN)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// The user at the other end of the connected socket `fd`, which a server checks is this one. `nil` when it can't tell.
    static func peerUser(of fd: Int32) -> uid_t? {
        var uid = uid_t()
        var gid = gid_t()
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
    }
}
