import Foundation

/// What the `warble` command line is asked, parsed from its arguments with no program name: a command that does what a
/// button does (`RemoteCommand`), or `now`, which reads. Both the command and the app parse the same arguments, so the
/// command line sends them as they were typed and a typo is refused with the same words wherever it's caught.
public enum WarbleCommand: Equatable, Sendable {
    /// What's playing, as text or, with `--json`, as a line of JSON.
    case now(json: Bool)
    case send(RemoteCommand)
    case version
    /// Help for one command, or for all of them.
    case help(String?)

    /// The commands, in the order help lists them.
    public static let names = ["now", "play", "pause", "toggle", "next", "previous", "seek", "volume", "output"]

    public static func parse(_ arguments: [String]) throws(RemoteCommandError) -> WarbleCommand {
        guard let first = arguments.first else {
            throw .usage(nil, "missing a command")
        }
        let rest = Array(arguments.dropFirst())
        switch first {
        case "--version", "-v", "version":
            guard rest.isEmpty else { throw .usage(nil, "--version takes no arguments") }
            return .version
        case "--help", "-h", "help":
            guard rest.count <= 1 else { throw .usage(nil, "help takes at most one command") }
            if let command = rest.first, !names.contains(command) {
                throw .usage(nil, "no command named \"\(command)\"")
            }
            return .help(rest.first)
        case "now":
            if rest.contains(where: isHelp) { return .help(first) }
            let flags = Set(rest)
            guard flags.isSubset(of: ["--json"]), flags.count == rest.count else {
                throw .usage(first, "takes only --json")
            }
            return .now(json: flags.contains("--json"))
        default:
            if rest.contains(where: isHelp) {
                guard names.contains(first) else { throw .usage(nil, "no command named \"\(first)\"") }
                return .help(first)
            }
            return .send(try RemoteCommand(arguments: arguments))
        }
    }

    private static func isHelp(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
    }

    /// The help for `command`, or for every command, with `program` as the name typed.
    public static func usage(_ command: String?, program: String = "warble") -> String {
        switch command {
        case "now": "Usage: \(program) now [--json]\nPrints what's playing. With --json, one line of JSON for a status bar, with the keys status, title, artist, album, app, position, duration, shuffle, repeat and volume."
        case "play", "pause", "toggle", "next", "previous":
            "Usage: \(program) \(command ?? "")\n" + summary(command)
        case "seek": "Usage: \(program) seek <seconds>\nMoves to a position in the track, in seconds from the start, such as 90 or 1:30."
        case "volume": "Usage: \(program) volume <0-100>\nSets the volume of the Mac's sound output."
        case "output": "Usage: \(program) output <name>\nMoves the Mac's sound to the output with that name, such as AirPods. A start of the name is enough when it's the only one."
        default:
            """
            Usage: \(program) <command>

            Commands:
              now [--json]       what's playing
              play               play
              pause              pause
              toggle             play or pause
              next               the next track
              previous           the previous track
              seek <seconds>     move to a position in the track
              volume <0-100>     set the volume
              output <name>      move the sound to another output

            Options:
              --version          Warble's version
              --help             this help, or \(program) <command> --help for one command

            The command line works while Settings › Developer › Allow the warble command is on.
            """
        }
    }

    private static func summary(_ command: String?) -> String {
        switch command {
        case "play": "Plays."
        case "pause": "Pauses."
        case "toggle": "Plays when paused, and pauses when playing."
        case "next": "Skips to the next track."
        default: "Goes to the previous track."
        }
    }
}

extension RemoteCommand {
    /// The command for `arguments`, which are a command's name and what follows it, or a `.usage` error that says what's
    /// wrong. The ones the command line has: `play`, `pause`, `toggle`, `next`, `previous`, `seek <seconds>`,
    /// `volume <0-100>` and `output <name>`.
    public init(arguments: [String]) throws(RemoteCommandError) {
        guard let name = arguments.first else {
            throw .usage(nil, "missing a command")
        }
        let rest = Array(arguments.dropFirst())
        func takesNothing(_ command: RemoteCommand) throws(RemoteCommandError) -> RemoteCommand {
            guard rest.isEmpty else { throw .usage(name, "takes no arguments") }
            return command
        }
        switch name {
        case "play": self = try takesNothing(.play)
        case "pause": self = try takesNothing(.pause)
        case "toggle": self = try takesNothing(.toggle)
        case "next": self = try takesNothing(.next)
        case "previous": self = try takesNothing(.previous)
        case "seek":
            guard rest.count == 1, let text = rest.first else { throw .usage(name, "expected a position in seconds, such as 90 or 1:30") }
            guard let seconds = Self.position(text) else {
                throw .usage(name, "\(text) isn't a position; use seconds from the start, such as 90, or minutes and seconds, such as 1:30")
            }
            self = .seek(seconds: seconds)
        case "volume":
            guard rest.count == 1, let text = rest.first else { throw .usage(name, "expected a volume from 0 to 100") }
            guard let percent = Self.percent(text.hasSuffix("%") ? String(text.dropLast()) : text) else {
                throw .usage(name, "\(text) isn't a volume; use a whole number from 0 to 100")
            }
            self = .volume(percent: percent)
        case "output":
            // A name with spaces needs no quotes, as `warble output MacBook Pro Speakers`.
            let output = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !output.isEmpty else { throw .usage(name, "expected the name of an output, such as AirPods") }
            self = .output(name: output)
        default:
            throw .usage(nil, "no command named \"\(name)\"")
        }
    }

    /// A position in `text`: seconds, such as `90` or `7.5`, or `m:ss` or `h:mm:ss`. `nil` for anything else.
    public static func position(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        if parts.count == 1 { return seconds(text) }
        var total = 0.0
        for part in parts.dropLast() {
            guard let whole = Int(part), whole >= 0 else { return nil }
            total = total * 60 + Double(whole)
        }
        guard let last = seconds(String(parts[parts.count - 1])) else { return nil }
        return total * 60 + last
    }
}
