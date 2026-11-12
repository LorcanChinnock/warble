import Foundation
import Testing
@testable import WarbleModel

private func offer(stage: UpdateOffer.Stage = .notDownloaded, size: UInt64? = 6_000_000, critical: Bool = false, major: Bool = false, infoOnly: Bool = false) -> UpdateOffer {
    UpdateOffer(
        version: "0.2.0", build: "200", installedVersion: "0.1.0-beta.14", installedBuild: "114", stage: stage,
        downloadSize: size, isCritical: critical, isMajorUpgrade: major, isInformationOnly: infoOnly
    )
}

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Test func anOfferHasSkipRemindMeTomorrowAndInstall() {
    let buttons = UpdateOfferButtons(offer: offer(), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(buttons.install == .installAndRelaunch)
    #expect(buttons.later == .remindTomorrow)
    #expect(buttons.showsSkip)
    #expect(buttons.showsAutomaticInstall)
}

@Test func remindMeTomorrowIsHiddenWithoutAutomaticChecks() {
    // It waits for the next scheduled check, and there isn't one.
    let buttons = UpdateOfferButtons(offer: offer(), automaticallyChecks: false, allowsAutomaticUpdates: false)
    #expect(buttons.later == .hidden)
    #expect(buttons.showsSkip)
    #expect(!buttons.showsAutomaticInstall)
}

@Test func anUnpackedUpdateInstallsOnQuitInsteadOfReminding() {
    #expect(UpdateOfferButtons(offer: offer(stage: .installing), automaticallyChecks: true, allowsAutomaticUpdates: true).later == .installOnQuit)
    #expect(UpdateOfferButtons(offer: offer(stage: .downloaded), automaticallyChecks: true, allowsAutomaticUpdates: true).later == .remindTomorrow)
}

@Test func aCriticalUpdateCantBeSkippedOrPutOff() {
    let critical = UpdateOfferButtons(offer: offer(critical: true), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(!critical.showsSkip)
    #expect(critical.later == .hidden)
    // A critical major upgrade can still be skipped, as in Sparkle.
    let major = UpdateOfferButtons(offer: offer(critical: true, major: true), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(major.showsSkip)
    #expect(major.later == .remindTomorrow)
}

@Test func anInformationOnlyUpdateOpensItsPage() {
    let buttons = UpdateOfferButtons(offer: offer(infoOnly: true), automaticallyChecks: true, allowsAutomaticUpdates: true)
    #expect(buttons.install == .learnMore)
    #expect(!buttons.showsAutomaticInstall)
    #expect(offer(infoOnly: true).message == .installedOnly)
}

@Test func theOfferMentionsTheSizeOnlyWhileThereIsADownloadToCome() {
    #expect(offer().message == .downloadAndRelaunch(size: 6_000_000))
    #expect(offer(size: nil).message == .relaunch)
    #expect(offer(size: 0).message == .relaunch)
    #expect(offer(stage: .downloaded).message == .relaunch)
    #expect(offer(stage: .installing).message == .relaunch)
}

@Test func offerVersionsAddBuildsWhenTheyReadTheSame() {
    #expect(offer().versions == ("0.2.0", "0.1.0-beta.14"))
    let same = UpdateOffer(version: "0.2.0", build: "201", installedVersion: "0.2.0", installedBuild: "200")
    #expect(same.versions == ("0.2.0 (201)", "0.2.0 (200)"))
}

@Test func downloadProgressCountsBytes() {
    var progress = UpdateDownloadProgress()
    #expect(progress.fraction == nil)
    progress.expect(1000)
    progress.receive(250, at: start)
    progress.receive(250, at: start)
    #expect(progress.fraction == 0.5)
    progress.receive(900, at: start)
    #expect(progress.fraction == 1)
    #expect(progress.received == 1400)
    #expect(progress.total == 1400)
}

@Test func downloadProgressWithoutASizeHasNoFractionOrTotal() {
    var progress = UpdateDownloadProgress()
    progress.expect(0)
    progress.receive(10, at: start)
    #expect(progress.fraction == nil)
    #expect(progress.total == nil)
    #expect(progress.secondsLeft(now: start.addingTimeInterval(5)) == nil)
}

@Test func timeLeftWaitsForASecondOfDataThenFollowsTheSpeed() {
    var progress = UpdateDownloadProgress()
    progress.expect(6_000_000)
    progress.receive(1_000_000, at: start)
    #expect(progress.secondsLeft(now: start.addingTimeInterval(0.5)) == nil)
    progress.receive(1_000_000, at: start.addingTimeInterval(2))
    // 2 MB in 2 seconds leaves 4 MB, about 4 seconds.
    #expect(progress.secondsLeft(now: start.addingTimeInterval(2)) == 4)
    progress.receive(4_000_000, at: start.addingTimeInterval(4))
    #expect(progress.secondsLeft(now: start.addingTimeInterval(4)) == nil)
}

@Test func timeLeftNeverReadsZeroWhileBytesAreStillToCome() {
    var progress = UpdateDownloadProgress()
    progress.expect(1_000_001)
    progress.receive(1_000_000, at: start)
    #expect(progress.secondsLeft(now: start.addingTimeInterval(10)) == 1)
}

@Test func closingTheWindowDoesWhatEachStateSays() {
    #expect(UpdatePhase.checking.closing == .cancel)
    #expect(UpdatePhase.offer.closing == .remindLater)
    // The download goes on with the window closed.
    #expect(UpdatePhase.downloading.closing == .hide)
    #expect(UpdatePhase.preparing(0.5).closing == .hide)
    // Later on Ready installs the update the next time Warble quits.
    #expect(UpdatePhase.ready.closing == .installOnQuit)
    #expect(UpdatePhase.installing.closing == .refuse)
    #expect(UpdatePhase.installedWhileRunning(version: "0.2.0").closing == .later)
}

@Test func onlyTheOfferIsTheWideWindow() {
    #expect(UpdatePhase.offer.width == 540)
    #expect(UpdatePhase.checking.width == 500)
    #expect(UpdatePhase.ready.width == 500)
}
