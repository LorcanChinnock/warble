import Foundation
import Testing
@testable import WarbleModel

@Test func aStreamThatExitsIsCheckedWithTestThenStartedAgain() {
    var supervisor = AdapterSupervisor()
    #expect(supervisor.streamExited(afterRunning: 300) == .runTest(after: 1))
    #expect(supervisor.testExited(status: 0) == .startStream)
}

@Test func eachExitInARowWaitsLongerThenGivesUp() {
    var supervisor = AdapterSupervisor()
    for delay in AdapterSupervisor.restartDelays {
        #expect(supervisor.streamExited(afterRunning: 0.5) == .runTest(after: delay))
        #expect(supervisor.testExited(status: 0) == .startStream)
    }
    #expect(supervisor.streamExited(afterRunning: 0.5) == .giveUp)
}

@Test func aStreamThatRanAWhileStartsTheCountAgain() {
    var supervisor = AdapterSupervisor()
    for _ in 0..<4 {
        _ = supervisor.streamExited(afterRunning: 0.5)
        _ = supervisor.testExited(status: 0)
    }
    #expect(supervisor.streamExited(afterRunning: AdapterSupervisor.steadyRun) == .runTest(after: 1))
}

@Test func aTestThatTimesOutIsTriedAgainAFewTimes() {
    for status: Int32 in [3, 4] {
        var supervisor = AdapterSupervisor()
        _ = supervisor.streamExited(afterRunning: 300)
        for delay in AdapterSupervisor.testRetryDelays {
            #expect(supervisor.testExited(status: status) == .runTest(after: delay))
        }
        #expect(supervisor.testExited(status: status) == .giveUp)
    }
}

@Test func aTestThatPassesOnRetryStartsTheStream() {
    var supervisor = AdapterSupervisor()
    _ = supervisor.streamExited(afterRunning: 300)
    #expect(supervisor.testExited(status: 4) == .runTest(after: 2))
    #expect(supervisor.testExited(status: 0) == .startStream)
}

@Test func eachExitGetsItsOwnTestRetries() {
    var supervisor = AdapterSupervisor()
    _ = supervisor.streamExited(afterRunning: 300)
    _ = supervisor.testExited(status: 4)
    _ = supervisor.testExited(status: 4)
    _ = supervisor.testExited(status: 0)
    _ = supervisor.streamExited(afterRunning: 300)
    #expect(supervisor.testExited(status: 4) == .runTest(after: 2))
}

@Test func aTestThatCantRunGivesUpAtOnce() {
    for status: Int32 in [1, 2, 255] {
        var supervisor = AdapterSupervisor()
        _ = supervisor.streamExited(afterRunning: 300)
        #expect(supervisor.testExited(status: status) == .giveUp)
    }
}

@Test func theSupervisorRemembersHowTheLastTestExited() {
    var supervisor = AdapterSupervisor()
    #expect(supervisor.lastTestStatus == nil)
    _ = supervisor.streamExited(afterRunning: 300)
    _ = supervisor.testExited(status: 1)
    #expect(supervisor.lastTestStatus == 1)
}

@Test func theBackendIsTheAdapterUntilItExits() {
    var supervisor = AdapterSupervisor()
    #expect(supervisor.backend == .adapter)
    _ = supervisor.streamExited(afterRunning: 300)
    #expect(supervisor.backend == .restarting)
    _ = supervisor.testExited(status: 0)
    #expect(supervisor.backend == .adapter)
}

@Test func aTestThatTimesOutKeepsRestartingUntilTheRetriesRunOut() {
    var supervisor = AdapterSupervisor()
    _ = supervisor.streamExited(afterRunning: 300)
    for _ in AdapterSupervisor.testRetryDelays {
        _ = supervisor.testExited(status: 3)
        #expect(supervisor.backend == .restarting)
    }
    _ = supervisor.testExited(status: 3)
    #expect(supervisor.backend == .script(because: .gaveUp(testStatus: 3)))
}

@Test func aTestThatCantRunSwitchesToAppleScript() {
    var supervisor = AdapterSupervisor()
    _ = supervisor.streamExited(afterRunning: 300)
    _ = supervisor.testExited(status: 1)
    #expect(supervisor.backend == .script(because: .gaveUp(testStatus: 1)))
}

@Test func tooManyExitsInARowSwitchToAppleScriptWithTheLastTestStatus() {
    var supervisor = AdapterSupervisor()
    for _ in AdapterSupervisor.restartDelays {
        _ = supervisor.streamExited(afterRunning: 0.5)
        _ = supervisor.testExited(status: 0)
    }
    _ = supervisor.streamExited(afterRunning: 0.5)
    #expect(supervisor.backend == .script(because: .gaveUp(testStatus: 0)))
}

@Test func anAdapterThatIsntBundledStartsOnAppleScript() {
    #expect(AdapterSupervisor(bundled: false).backend == .script(because: .notBundled))
}
