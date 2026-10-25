import AppKit
import Darwin
import Foundation
import os
import QuartzCore

/// Signposts around launch, expand and play/pause. Instruments shows them. They cost almost nothing
/// when nobody reads them, and nothing at all while nobody touches the notch, so they never wake Warble while nothing
/// is playing.
@MainActor
enum Perf {
    static let signposter = OSSignposter(logger: .warble("perf"))

    /// Milliseconds since the kernel started this process, so launch time includes what runs before `main`.
    nonisolated static func millisecondsSinceLaunch() -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Int((Date().timeIntervalSince1970 - started) * 1000)
    }

    /// Times a change from now until the next frame of `screen` after it, which is when the change starts to show. Call it
    /// just after making the change: the frame comes once this turn of the run loop has committed it. The interval runs
    /// from the call, and its end message gives `cause` and the milliseconds since `start`, a time on the clock of
    /// `ProcessInfo.systemUptime` such as an event's timestamp, or since the call without one.
    static func untilNextFrame(_ name: StaticString, on screen: NSScreen?, cause: String, since start: TimeInterval? = nil) {
        guard signposter.isEnabled, let screen else { return }
        let begun = ProcessInfo.processInfo.systemUptime
        let interval = signposter.beginInterval(name, id: signposter.makeSignpostID())
        NextFrame.after(on: screen) {
            let ms = (ProcessInfo.processInfo.systemUptime - (start ?? begun)) * 1000
            signposter.endInterval(name, interval, "\(cause, privacy: .public) ms=\(ms, format: .fixed(precision: 1))")
        }
    }

    /// The click or key being handled and its timestamp, for `untilNextFrame`, or `nil` outside of one, such as for a
    /// global shortcut.
    static var input: (cause: String, timestamp: TimeInterval)? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .leftMouseDown, .leftMouseUp: return ("click", event.timestamp)
        case .keyDown: return ("key", event.timestamp)
        default: return nil
        }
    }
}

/// Calls its body at the next frame of a display, once, through a display link that goes away after it.
@MainActor
private final class NextFrame: NSObject {
    private let body: () -> Void

    private init(body: @escaping () -> Void) {
        self.body = body
    }

    static func after(on screen: NSScreen, _ body: @escaping () -> Void) {
        // The link holds its target until it's invalidated.
        let link = screen.displayLink(target: NextFrame(body: body), selector: #selector(fire))
        link.add(to: .main, forMode: .common)
    }

    @objc private func fire(_ link: CADisplayLink) {
        link.invalidate()
        body()
    }
}
