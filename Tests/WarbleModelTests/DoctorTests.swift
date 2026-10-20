import Foundation
import Testing
@testable import WarbleModel

private let tahoe = Doctor.Version(26, 1)

@Test func everyCheckPassesWhileTheAdapterWorks() {
    let checks = Doctor.checks(Doctor.Facts(adapter: .working, macOS: tahoe, automation: [.spotify: .denied]))
    #expect(checks.map(\.kind) == Doctor.Kind.allCases)
    #expect(checks.map(\.outcome) == [.pass, .pass, .pass, .pass])
    #expect(checks.map(\.finding) == [.adapterWorking, .macOSSupported(tahoe), .automationNotNeeded, .playersAny])
    #expect(!Doctor.needsAttention(checks))
}

@Test func aMissingAdapterFailsWithAReinstall() {
    let check = Doctor.adapter(Doctor.Facts(adapter: .missing, macOS: tahoe))
    #expect(check == Doctor.Check(.adapter, .fail, .adapterMissing, fix: .reinstall))
}

@Test func anAdapterMacOSWontRunAsksForAnUpdate() {
    for status: Int32 in [1, 2, -1] {
        let check = Doctor.adapter(Doctor.Facts(adapter: .stopped(testStatus: status), macOS: tahoe))
        #expect(check == Doctor.Check(.adapter, .fail, .adapterBlocked, fix: .checkForUpdates))
    }
}

@Test func anAdapterThatKeptStoppingAsksToOpenWarbleAgain() {
    for status: Int32? in [0, 3, 4, nil] {
        let check = Doctor.adapter(Doctor.Facts(adapter: .stopped(testStatus: status), macOS: tahoe))
        #expect(check == Doctor.Check(.adapter, .fail, .adapterUnsteady, fix: .openAgain))
    }
}

@Test func aNewerMacOSIsOnlyAWarningWhenTheAdapterStopped() {
    let newer = Doctor.Version(Doctor.newestTestedMacOS + 1, 0)
    #expect(Doctor.macOS(Doctor.Facts(adapter: .working, macOS: newer)).outcome == .pass)
    let check = Doctor.macOS(Doctor.Facts(adapter: .stopped(testStatus: 1), macOS: newer))
    #expect(check == Doctor.Check(.macOS, .warn, .macOSNewer(newer), fix: .checkForUpdates))
}

@Test func deniedAutomationFailsWithTheSettingsToChange() {
    let facts = Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.music: .allowed, .spotify: .denied])
    let check = Doctor.automation(facts)
    #expect(check == Doctor.Check(.automation, .fail, .automationDenied([.spotify]), fix: .openAutomationSettings))
    #expect(Doctor.needsAttention([check]))
}

@Test func automationPassesOnceAllowedOrBeforeMacOSHasAsked() {
    let allowed = Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.music: .allowed, .spotify: .notAsked])
    #expect(Doctor.automation(allowed) == Doctor.Check(.automation, .pass, .automationAllowed([.music])))
    let notAsked = Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.spotify: .notAsked])
    #expect(Doctor.automation(notAsked) == Doctor.Check(.automation, .pass, .automationNotAsked([.spotify])))
}

@Test func automationIsUnknownUntilAPlayerIsOpen() {
    let check = Doctor.automation(Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.music: .notRunning]))
    #expect(check == Doctor.Check(.automation, .unknown, .automationUnknown))
}

@Test func theFallbackWarnsWhichPlayersItFollows() {
    let open = Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.music: .notRunning, .spotify: .allowed])
    #expect(Doctor.players(open) == Doctor.Check(.players, .warn, .playersFollowing([.spotify])))
    let closed = Doctor.Facts(adapter: .missing, macOS: tahoe)
    #expect(Doctor.players(closed) == Doctor.Check(.players, .warn, .playersNoneOpen, fix: .openPlayer(.music)))
}

@Test func aPlayerWarbleMayNotControlIsntFollowed() {
    let denied = Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.music: .denied, .spotify: .allowed])
    #expect(Doctor.players(denied) == Doctor.Check(.players, .warn, .playersFollowing([.spotify])))
    // Opening it again wouldn't help, so there's no button.
    let onlyDenied = Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.music: .denied])
    #expect(Doctor.players(onlyDenied) == Doctor.Check(.players, .warn, .playersNoneOpen))
}

@Test func onlyAFailureTheUserHasntPutOffNeedsAttention() {
    let checks = Doctor.checks(Doctor.Facts(adapter: .missing, macOS: tahoe, automation: [.spotify: .denied]))
    #expect(Doctor.needsAttention(checks))
    #expect(Doctor.needsAttention(checks, dismissed: [.adapter]))
    #expect(!Doctor.needsAttention(checks, dismissed: [.adapter, .automation]))
}

@Test func aVersionReadsAsMacOSWritesIt() {
    #expect(Doctor.Version(26, 1).description == "26.1")
    #expect(Doctor.Version(27, 0, 1).description == "27.0.1")
}
