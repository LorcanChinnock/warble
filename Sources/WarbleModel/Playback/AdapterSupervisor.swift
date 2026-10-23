import Foundation

/// Decides what to do when the adapter's `stream` exits without being asked to: check with `test` that the adapter
/// still works, then start the stream again, waiting longer after each exit in a row and giving up after a few.
///
/// `test` times out now and then on an adapter that works (exit 3 or 4, when the test client is slow to start), so
/// those exits are tried again a couple of times before giving up. Any other failure means the adapter can't run here,
/// such as a framework that won't load, and Warble stops using it until it's opened again.
public struct AdapterSupervisor: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case runTest(after: TimeInterval)
        case startStream
        case giveUp
    }

    /// Which backend follows what's playing, and why, so there is one place that answers it.
    public enum Backend: Equatable, Sendable {
        /// The adapter's stream is running, or about to start.
        case adapter
        /// The stream exited; Warble is waiting to check with `test` and start it again.
        case restarting
        /// AppleScript follows Music and Spotify instead.
        case script(because: Reason)
    }

    public enum Reason: Equatable, Sendable {
        /// The adapter isn't in the app, as when a file of it has been removed.
        case notBundled
        /// Warble gave up on the adapter until it's opened again. `testStatus` is how its last `test` exited, `nil` if
        /// none ran.
        case gaveUp(testStatus: Int32?)
    }

    /// The waits before each restart in a row; one more exit in a row gives up.
    public static let restartDelays: [TimeInterval] = [1, 2, 4, 8, 16]
    /// A stream that ran this long before it exited starts the count of exits in a row again.
    public static let steadyRun: TimeInterval = 60
    /// The waits before trying a `test` that timed out again.
    public static let testRetryDelays: [TimeInterval] = [2, 10]

    private var restarts = 0
    private var testRetries = 0
    /// How the last `test` exited, which tells the Doctor why Warble gave up; `nil` until one has run.
    public private(set) var lastTestStatus: Int32?

    public private(set) var backend: Backend

    public init(bundled: Bool = true) {
        backend = bundled ? .adapter : .script(because: .notBundled)
    }

    public mutating func streamExited(afterRunning duration: TimeInterval) -> Step {
        if duration >= Self.steadyRun {
            restarts = 0
        }
        guard restarts < Self.restartDelays.count else { return giveUp() }
        defer { restarts += 1 }
        testRetries = 0
        backend = .restarting
        return .runTest(after: Self.restartDelays[restarts])
    }

    public mutating func testExited(status: Int32) -> Step {
        lastTestStatus = status
        switch status {
        case 0:
            backend = .adapter
            return .startStream
        // 3: the test client didn't signal within 3 seconds. 4: it did, but the adapter read nothing 10 ms later.
        case 3, 4:
            guard testRetries < Self.testRetryDelays.count else { return giveUp() }
            defer { testRetries += 1 }
            return .runTest(after: Self.testRetryDelays[testRetries])
        // 1: the script failed, such as a framework that won't load. 2: the test client wouldn't launch.
        default:
            return giveUp()
        }
    }

    private mutating func giveUp() -> Step {
        backend = .script(because: .gaveUp(testStatus: lastTestStatus))
        return .giveUp
    }
}
