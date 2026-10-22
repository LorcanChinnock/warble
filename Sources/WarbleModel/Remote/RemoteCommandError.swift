import Foundation

/// Why a command didn't run, with the exit code the `warble` command ends with, which follow `sysexits.h`.
public enum RemoteCommandError: Error, Equatable, Sendable {
    /// A bad command, a missing argument or a value out of range; the command it was for, if any.
    case usage(String?, String)
    /// Warble isn't running, or the command line is off in Settings, so nothing answers.
    case unavailable(String)
    /// The socket can't be made: something is in the way, or its folder isn't writable.
    case cantCreate(String)
    /// Reading or writing failed partway.
    case io(String)
    case `internal`(String)

    public var exitCode: Int32 {
        switch self {
        case .usage: 64
        case .unavailable: 69
        case .internal: 70
        case .cantCreate: 73
        case .io: 74
        }
    }

    public var message: String {
        switch self {
        case .usage(_, let message), .unavailable(let message), .cantCreate(let message), .io(let message), .internal(let message):
            message
        }
    }

    /// The error with `exitCode`, as the app sends it back to the command line. An unknown code is `.internal`.
    public init(exitCode: Int32, message: String) {
        self = switch exitCode {
        case 64: .usage(nil, message)
        case 69: .unavailable(message)
        case 73: .cantCreate(message)
        case 74: .io(message)
        default: .internal(message)
        }
    }
}
