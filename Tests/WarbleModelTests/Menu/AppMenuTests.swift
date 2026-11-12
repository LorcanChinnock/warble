import Foundation
import Testing
@testable import WarbleModel

private func update(pending: String? = nil, canCheck: Bool = true, phase: UpdatePhase? = nil, fraction: Double? = nil) -> UpdateMenuItem {
    UpdateMenuItem(pendingVersion: pending, canCheck: canCheck, phase: phase, version: "0.2.0", fraction: fraction)
}

@Test func theMenuBarMenuIsInTheConventionalOrder() {
    #expect(AppMenu.items(update: .check(enabled: true)) == [.about, .update(.check(enabled: true)), .separator, .settings, .separator, .quit])
}

@Test func theRightClickMenuPutsTheSongFirstThenTheMenuBarMenu() {
    let update = UpdateMenuItem.check(enabled: true)
    #expect(AppMenu.items(update: update, openApp: true, copySong: true) == [.openApp, .copySong, .separator] + AppMenu.items(update: update))
    #expect(AppMenu.items(update: update, openApp: true, copySong: false) == [.openApp, .separator] + AppMenu.items(update: update))
    #expect(AppMenu.items(update: update, openApp: false, copySong: true) == [.copySong, .separator] + AppMenu.items(update: update))
}

@Test func theRightClickMenuWithNoSongIsTheMenuBarMenu() {
    let update = UpdateMenuItem.waiting(version: "0.2.0")
    #expect(AppMenu.items(update: update, openApp: false, copySong: false) == AppMenu.items(update: update))
}

@Test func withNothingUnderWayTheItemChecksForUpdates() {
    #expect(update() == .check(enabled: true))
    #expect(update().isEnabled)
    #expect(!update().hasDot)
}

@Test func checkForUpdatesIsDimmedWhileSparkleCantCheck() {
    #expect(update(canCheck: false) == .check(enabled: false))
    #expect(!update(canCheck: false).isEnabled)
}

@Test func aWaitingUpdateReplacesCheckForUpdatesWithADot() {
    let item = update(pending: "0.2.0", canCheck: false)
    #expect(item == .waiting(version: "0.2.0"))
    #expect(item.isEnabled)
    #expect(item.hasDot)
}

@Test func aDownloadShowsItsProgressRoundedDown() {
    #expect(update(phase: .downloading, fraction: 0.539) == .downloading(version: "0.2.0", percent: 53))
    #expect(update(phase: .downloading, fraction: 0.999) == .downloading(version: "0.2.0", percent: 99))
    #expect(update(phase: .downloading, fraction: 0) == .downloading(version: "0.2.0", percent: 0))
}

@Test func aDownloadOfUnknownSizeShowsNoPercentage() {
    #expect(update(phase: .downloading) == .downloading(version: "0.2.0", percent: nil))
}

@Test func unpackingTheDownloadShowsAsAFinishedDownload() {
    #expect(update(phase: .preparing(0.4)) == .downloading(version: "0.2.0", percent: 100))
}

@Test func aDownloadWinsOverAWaitingUpdateAndHasNoDot() {
    let item = update(pending: "0.2.0", canCheck: false, phase: .downloading, fraction: 0.5)
    #expect(item == .downloading(version: "0.2.0", percent: 50))
    #expect(item.isEnabled)
    #expect(!item.hasDot)
}

@Test func onlyDownloadingAndUnpackingCountAsADownload() {
    #expect(UpdatePhase.downloading.isDownloading)
    #expect(UpdatePhase.preparing(0.5).isDownloading)
    for phase in [UpdatePhase.checking, .offer, .ready, .installing, .installedWhileRunning(version: "0.2.0")] {
        #expect(!phase.isDownloading)
    }
}

@Test func theWindowsOtherStatesLeaveTheItemAsItWas() {
    for phase in [UpdatePhase.checking, .offer, .ready, .installing, .installedWhileRunning(version: "0.2.0")] {
        #expect(update(phase: phase) == .check(enabled: true))
        #expect(update(pending: "0.2.0", phase: phase) == .waiting(version: "0.2.0"))
    }
}
