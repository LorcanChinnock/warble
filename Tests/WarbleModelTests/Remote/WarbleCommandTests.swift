import Foundation
import Testing
@testable import WarbleModel

private func parse(_ arguments: String...) throws -> WarbleCommand {
    try WarbleCommand.parse(arguments)
}

private func usage(_ arguments: String...) -> RemoteCommandError? {
    do {
        _ = try WarbleCommand.parse(arguments)
        return nil
    } catch {
        return error
    }
}

@Test func eachCommandParsesAndDispatchesWhatItsButtonDoes() throws {
    #expect(try parse("toggle") == .send(.toggle))
    #expect(try parse("play") == .send(.play))
    #expect(try parse("pause") == .send(.pause))
    #expect(try parse("next") == .send(.next))
    #expect(try parse("previous") == .send(.previous))
    #expect(try parse("seek", "90") == .send(.seek(seconds: 90)))
    #expect(try parse("volume", "40") == .send(.volume(percent: 40)))
    #expect(try parse("output", "AirPods") == .send(.output(name: "AirPods")))
    #expect(RemoteCommand.toggle.action == .perform(.playPause))
    #expect(RemoteCommand.play.action == .command(.play))
    #expect(RemoteCommand.pause.action == .command(.pause))
    #expect(RemoteCommand.next.action == .perform(.nextTrack))
    #expect(RemoteCommand.previous.action == .perform(.previousTrack))
    #expect(RemoteCommand.seek(seconds: 90).action == .command(.seek(to: 90)))
    #expect(RemoteCommand.volume(percent: 40).action == .setVolume(0.4))
}

@Test func nowTakesOnlyJSON() throws {
    #expect(try parse("now") == .now(json: false))
    #expect(try parse("now", "--json") == .now(json: true))
    #expect(usage("now", "--verbose") == .usage("now", "takes only --json"))
    #expect(usage("now", "--json", "--json") != nil)
}

@Test func aPositionIsSecondsOrMinutesAndSeconds() throws {
    #expect(try parse("seek", "7.5") == .send(.seek(seconds: 7.5)))
    #expect(try parse("seek", "0") == .send(.seek(seconds: 0)))
    #expect(try parse("seek", "1:30") == .send(.seek(seconds: 90)))
    #expect(try parse("seek", "1:02:03") == .send(.seek(seconds: 3723)))
}

@Test func aVolumeMayEndInAPercentSign() throws {
    #expect(try parse("volume", "40%") == .send(.volume(percent: 40)))
    #expect(try parse("volume", "0") == .send(.volume(percent: 0)))
    #expect(try parse("volume", "100") == .send(.volume(percent: 100)))
}

@Test func anOutputNameNeedsNoQuotes() throws {
    #expect(try parse("output", "MacBook", "Air", "Speakers") == .send(.output(name: "MacBook Air Speakers")))
    #expect(try parse("output", "MacBook Air Speakers") == .send(.output(name: "MacBook Air Speakers")))
}

@Test func badInputGivesAClearError() {
    #expect(usage() == .usage(nil, "missing a command"))
    #expect(usage("dance") == .usage(nil, "no command named \"dance\""))
    #expect(usage("toggle", "now") == .usage("toggle", "takes no arguments"))
    #expect(usage("seek") == .usage("seek", "expected a position in seconds, such as 90 or 1:30"))
    #expect(usage("seek", "soon")?.message.contains("soon isn't a position") == true)
    #expect(usage("seek", "-5") != nil)
    #expect(usage("seek", "1", "2") != nil)
    #expect(usage("seek", "1:xx") != nil)
    #expect(usage("seek", "1:2:3:4") != nil)
    #expect(usage("seek", "nan") != nil)
    #expect(usage("volume") == .usage("volume", "expected a volume from 0 to 100"))
    #expect(usage("volume", "101")?.message.contains("101 isn't a volume") == true)
    #expect(usage("volume", "-1") != nil)
    #expect(usage("volume", "loud") != nil)
    #expect(usage("volume", "4.5") != nil)
    #expect(usage("output") == .usage("output", "expected the name of an output, such as AirPods"))
    #expect(usage("output", "  ") != nil)
}

@Test func everyBadInputIsAUsageError() {
    for arguments in [[], ["dance"], ["seek"], ["volume", "x"], ["output"], ["next", "now"]] {
        #expect(usage(arguments: arguments)?.exitCode == 64)
    }
}

private func usage(arguments: [String]) -> RemoteCommandError? {
    do {
        _ = try WarbleCommand.parse(arguments)
        return nil
    } catch {
        return error
    }
}

@Test func versionAndHelpParse() throws {
    #expect(try parse("--version") == .version)
    #expect(try parse("version") == .version)
    #expect(try parse("--help") == .help(nil))
    #expect(try parse("help") == .help(nil))
    #expect(try parse("help", "seek") == .help("seek"))
    #expect(try parse("seek", "--help") == .help("seek"))
    #expect(try parse("now", "-h") == .help("now"))
    #expect(usage("help", "dance") != nil)
    #expect(usage("dance", "--help") != nil)
    #expect(usage("--version", "x") != nil)
}

@Test func theHelpNamesEveryCommand() {
    let help = WarbleCommand.usage(nil)
    for name in WarbleCommand.names {
        #expect(help.contains(name))
        #expect(WarbleCommand.usage(name).hasPrefix("Usage: warble \(name)"))
    }
    #expect(WarbleCommand.usage(nil, program: "warble-dev").hasPrefix("Usage: warble-dev <command>"))
}

@Test func errorsKeepTheirExitCodeThroughTheSocket() {
    for error: RemoteCommandError in [.usage(nil, "a"), .unavailable("b"), .cantCreate("c"), .io("d"), .internal("e")] {
        let back = RemoteCommandError(exitCode: error.exitCode, message: error.message)
        #expect(back.exitCode == error.exitCode)
        #expect(back.message == error.message)
    }
    #expect(RemoteCommandError(exitCode: 1, message: "x") == .internal("x"))
}
