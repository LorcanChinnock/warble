import Foundation

/// A player the notch can follow, shown as a chip in the open card while more than one app plays.
public struct SourceChip: Equatable, Sendable {
    public var bundleIdentifier: String
    /// Whether the notch follows this app now, which gives its chip the full controls.
    public var isFollowed: Bool

    public init(bundleIdentifier: String, isFollowed: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.isFollowed = isFollowed
    }
}
