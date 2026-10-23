import Foundation

/// What the `warble` command asks the running app over its socket: one JSON line per connection, answered by one
/// `RemoteResponse` line. The request is the arguments as they were typed, so the app parses them with the same
/// `WarbleCommand` the command line did. Here, with no socket, so every message is tested on Linux.
public struct RemoteRequest: Codable, Equatable, Sendable {
    /// The protocol's version. A request with another is refused, so an old app never half-understands a new command line.
    public static let version = 1

    public var v: Int
    /// The arguments after the program name.
    public var arguments: [String]

    public init(arguments: [String]) {
        v = Self.version
        self.arguments = arguments
    }

    /// The request as one line, newline included.
    public var line: Data {
        // A struct of strings and a number always encodes.
        ((try? JSONEncoder().encode(self)) ?? Data()) + Data("\n".utf8)
    }

    /// The request in `data`, or a `.usage` error saying what's wrong with it.
    public static func decode(_ data: Data) throws(RemoteCommandError) -> RemoteRequest {
        guard let request = try? JSONDecoder().decode(RemoteRequest.self, from: data) else {
            throw .usage(nil, "the request isn't one Warble understands")
        }
        guard request.v == version else {
            throw .usage(nil, "this Warble speaks only version \(version) of the command line's protocol; update Warble or the command so they match")
        }
        return request
    }
}

/// The app's answer: what's playing for `now`, nothing more for a command that ran, or an error with its exit code.
public struct RemoteResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var now: NowPlayingSnapshot?
    public var code: Int32?
    public var error: String?

    public static func success(now: NowPlayingSnapshot? = nil) -> RemoteResponse {
        RemoteResponse(ok: true, now: now)
    }

    public static func failure(_ error: RemoteCommandError) -> RemoteResponse {
        RemoteResponse(ok: false, code: error.exitCode, error: error.message)
    }

    /// The response as one line, newline included.
    public var line: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return ((try? encoder.encode(self)) ?? Data()) + Data("\n".utf8)
    }

    /// The response in `data`, or an `.io` error when it isn't one.
    public static func decode(_ data: Data) throws(RemoteCommandError) -> RemoteResponse {
        guard let response = try? JSONDecoder().decode(RemoteResponse.self, from: data) else {
            throw .io("Warble's answer wasn't one this command understands; update Warble or the command so they match")
        }
        return response
    }

    /// What the command line makes of the answer: the snapshot for a `now`, nothing for a command, or the error.
    public func result() throws(RemoteCommandError) -> NowPlayingSnapshot? {
        guard ok else {
            throw RemoteCommandError(exitCode: code ?? 70, message: error ?? "Warble couldn't do that")
        }
        return now
    }
}
