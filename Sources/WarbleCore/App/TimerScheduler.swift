import Foundation
import WarbleModel

/// The clock on the wall.
public struct SystemClock: WallClock {
    public init() {}

    public var now: Date { .now }
}

/// One `Timer` on the main run loop, in the common modes so it fires while a menu tracks the pointer, replaced on each
/// call and gone while nothing is due.
@MainActor
public final class TimerScheduler: Scheduler {
    private var timer: Timer?

    public init() {}

    public func schedule(at deadline: Date?, _ fire: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = nil
        guard let deadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                fire()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
