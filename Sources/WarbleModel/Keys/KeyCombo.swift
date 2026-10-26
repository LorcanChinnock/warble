import Foundation

/// A key code plus Carbon modifier mask, as used by `RegisterEventHotKey`.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public static let command: UInt32 = 1 << 8

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
