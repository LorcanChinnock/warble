import Foundation
import Testing
@testable import WarbleModel

private func makeFolder() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cl-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

private let cli = "/Applications/Warble.app/Contents/MacOS/warble-cli"

@Test func aReleaseGetsWarbleAndADevBuildWarbleDev() {
    #expect(CommandLink.name(bundleID: "dev.lorcan.Warble") == "warble")
    #expect(CommandLink.name(bundleID: "dev.lorcan.Warble.dev") == "warble-dev")
    #expect(CommandLink.name(bundleID: nil) == "warble-dev")
}

@Test func withNothingThereItCanBeInstalled() throws {
    #expect(CommandLink.status(name: "warble", cli: cli, folder: try makeFolder(), homebrewFolder: try makeFolder()) == .missing)
}

@Test func aLinkToThisAppIsLinked() throws {
    let folder = try makeFolder()
    try FileManager.default.createSymbolicLink(atPath: folder + "/warble", withDestinationPath: cli)
    #expect(CommandLink.status(name: "warble", cli: cli, folder: folder, homebrewFolder: try makeFolder()) == .linked)
}

@Test func homebrewsLinkNeedsNothing() throws {
    let brew = try makeFolder()
    try FileManager.default.createSymbolicLink(atPath: brew + "/warble", withDestinationPath: cli)
    #expect(CommandLink.status(name: "warble", cli: cli, folder: try makeFolder(), homebrewFolder: brew) == .homebrew)
}

@Test func aLinkToAnotherCopyOfWarbleIsStale() throws {
    let folder = try makeFolder()
    let old = "/Users/someone/Old/Warble.app/Contents/MacOS/warble-cli"
    try FileManager.default.createSymbolicLink(atPath: folder + "/warble", withDestinationPath: old)
    #expect(CommandLink.status(name: "warble", cli: cli, folder: folder, homebrewFolder: try makeFolder()) == .stale(old))
}

@Test func someoneElsesCommandIsLeftAlone() throws {
    let folder = try makeFolder()
    try Data().write(to: URL(fileURLWithPath: folder + "/warble"))
    #expect(CommandLink.status(name: "warble", cli: cli, folder: folder, homebrewFolder: try makeFolder()) == .taken(folder + "/warble"))
}

@Test func theScriptsAskForAPasswordAndQuoteEveryPath() {
    let install = CommandLink.installScript(name: "warble", cli: "/Apps/It's Warble.app/Contents/MacOS/warble-cli")
    #expect(install.hasPrefix("do shell script "))
    #expect(install.hasSuffix(" with administrator privileges"))
    #expect(install.contains("ln -sfn"))
    #expect(install.contains("/usr/local/bin/warble"))
    #expect(install.contains(#"It'\\''s Warble.app"#))
    #expect(CommandLink.uninstallScript(name: "warble").contains("rm -f '/usr/local/bin/warble'"))
}
