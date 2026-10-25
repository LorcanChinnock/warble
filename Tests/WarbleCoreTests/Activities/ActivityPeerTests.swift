import Darwin
import Foundation
import Testing
import WarbleModel
@testable import WarbleCore

private func sender(_ executable: String, team: String? = "TEAM123456", identifier: String? = "com.example.app") -> ActivitySender {
    ActivityPeer.classify(ActivityPeer.Facts(executable: executable, teamID: team, signingIdentifier: identifier), client: 4)
}

@Test func aSignedAppInATopLevelBundleIsKnownByItsSignature() {
    let sender = sender("/Applications/Shot.app/Contents/MacOS/Shot", identifier: "dev.lorcan.Shot")
    #expect(sender.identifier == "TEAM123456.dev.lorcan.Shot")
    #expect(sender.bundleIdentifier == "dev.lorcan.Shot")
    #expect(sender.name == "Shot")
    #expect(sender.client == 4)
}

@Test func anAppInAUserFolderCountsToo() {
    #expect(sender("/Users/me/Applications/Some App.app/Contents/MacOS/x").bundleIdentifier != nil)
}

@Test func aHelperNestedInAnotherBundleIsAScript() {
    for path in [
        "/Applications/Shot.app/Contents/Library/LoginItems/Helper.app/Contents/MacOS/Helper",
        "/Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python",
        "/Applications/Shot.app/Contents/Frameworks/X.framework/Resources/Y.app/Contents/MacOS/Y",
    ] {
        let sender = sender(path)
        #expect(sender.bundleIdentifier == nil)
        #expect(sender.identifier == path)
    }
}

@Test func aProgramNotInAnAppBundleIsAScriptKeyedByItsPath() {
    let sender = sender("/usr/bin/python3", team: nil, identifier: nil)
    #expect(sender.bundleIdentifier == nil)
    #expect(sender.identifier == "/usr/bin/python3")
}

@Test func aSignedProgramWithoutATeamIDOrAnAppIsAScript() {
    #expect(sender("/Applications/Shot.app/Contents/MacOS/Shot", team: nil).bundleIdentifier == nil)
    #expect(sender("/opt/homebrew/bin/node", team: "TEAM123456", identifier: "node").bundleIdentifier == nil)
}

@Test func anExecutableThatIsNotTheBundlesMainOneIsAScript() {
    #expect(sender("/Applications/Shot.app/Contents/Resources/tool").bundleIdentifier == nil)
}

@Test func anInterpreterBundleIsAScriptEvenInAnAppFolder() {
    #expect(sender("/Applications/Python 3.13/IDLE.app/Contents/MacOS/IDLE", identifier: "org.python.python").bundleIdentifier == nil)
}

@Test func thisProcessIsAScriptKeyedByItsExecutable() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ap-\(UUID().uuidString.prefix(8))").appendingPathComponent("a.sock")
    defer { unlink(url.path) }
    let listener = try UnixSocket.listen(at: url, purpose: "tests")
    defer { close(listener) }
    let client = try UnixSocket.connect(to: url)
    defer { close(client) }
    var accepted: Int32 = -1
    for _ in 0 ..< 100 where accepted < 0 {
        accepted = accept(listener, nil, nil)
        if accepted < 0 { usleep(10_000) }
    }
    defer { close(accepted) }
    let sender = ActivityPeer.identify(accepted, client: 9)
    // The test runner is an Apple tool outside a top-level app bundle, so it's a script.
    #expect(sender.client == 9)
    #expect(sender.bundleIdentifier == nil)
    #expect(sender.identifier.hasPrefix("/"))
}
