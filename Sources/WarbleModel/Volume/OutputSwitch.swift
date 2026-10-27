import Foundation

/// A switch of output the listener asked for, watched for the moment macOS puts the old output back. It does that to
/// in-ear AirPods, and any app that sets the default output through Core Audio can't stop it; only System Settings can.
public struct OutputSwitch: Equatable, Sendable {
    /// How long after a switch a return to the old output counts as macOS undoing it: it comes within a second.
    public static let watchWindow: TimeInterval = 1.5
    /// How long an open card stays open for the note to be read, whatever the pointer does.
    public static let holdDuration: TimeInterval = 5
    /// How long the note about it stays.
    public static let noteDuration: TimeInterval = 5

    private struct Watch: Equatable, Sendable {
        let target: UInt32
        let previous: UInt32
        let until: Date
    }

    private var watch: Watch?
    private var noteUntil: Date?
    /// The output macOS kept, while the note shows; `nil` otherwise.
    public private(set) var kept: UInt32?

    public init() {}

    /// The listener chose `target` while `current` played.
    mutating func select(_ target: UInt32, from current: UInt32?, at now: Date) {
        self = OutputSwitch()
        if let current, current != target {
            watch = Watch(target: target, previous: current, until: now + Self.watchWindow)
        }
    }

    /// The outputs were read, with `current` playing.
    mutating func observe(current: UInt32?, at now: Date) {
        guard let watch, now < watch.until else { return }
        if current == watch.previous {
            kept = watch.previous
            noteUntil = now + Self.noteDuration
            self.watch = nil
        } else if current != watch.target {
            // Somewhere else, such as a device that came or went: not ours to explain.
            self.watch = nil
        }
    }

    mutating func advance(to now: Date) {
        if let until = watch?.until, until <= now { watch = nil }
        if let until = noteUntil, until <= now { self = OutputSwitch() }
    }

    /// When the watch ends or the note goes, or `nil`.
    var deadline: Date? {
        [watch?.until, noteUntil].compactMap { $0 }.min()
    }
}
