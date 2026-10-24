import Foundation
import Testing
@testable import WarbleModel

/// Every command, with how it's typed in Terminal and its link, which the command line and link reference
/// (site/src/guide/33-command-and-link-reference.md) list. Renaming one fails these tests, so it has to be made on
/// purpose, in the reference and for everyone's scripts.
private let commands: [(command: RemoteCommand, arguments: [String]?, link: String?)] = [
    (.toggle, ["toggle"], "warble://toggle"),
    (.play, ["play"], "warble://play"),
    (.pause, ["pause"], "warble://pause"),
    (.next, ["next"], "warble://next"),
    (.previous, ["previous"], "warble://previous"),
    (.seek(seconds: 90), ["seek", "90"], "warble://seek?seconds=90"),
    (.volume(percent: 40), ["volume", "40"], "warble://volume?percent=40"),
    (.output(name: "AirPods"), ["output", "AirPods"], nil),
    (.expand, nil, "warble://expand"),
    (.settings(section: nil), nil, "warble://settings"),
    (.settings(section: "shortcuts"), nil, "warble://settings?section=shortcuts"),
]

@Test func everyCommandKeepsItsNameOnTheCommandLine() throws {
    for case let (command, arguments?, _) in commands {
        #expect(try RemoteCommand(arguments: arguments) == command)
    }
}

@Test func everyCommandKeepsItsLinkRoute() throws {
    for case let (command, _, link?) in commands {
        #expect(RemoteCommand(url: try #require(URL(string: link))) == command)
    }
}

@Test func theCommandLineListsExactlyTheCommandsThatHaveANameThere() {
    let typed = commands.compactMap { $0.arguments?.first }
    #expect(WarbleCommand.names.sorted() == (["now"] + typed).sorted())
}

@Test func theSettingsSectionsKeepTheirNames() {
    #expect(RemoteCommand.settingsSections == ["general", "notch", "shortcuts", "developer", "about"])
}

@Test func theSchemesKeepTheirNames() {
    #expect(RemoteCommand.schemes == ["warble", "warble-dev"])
}
