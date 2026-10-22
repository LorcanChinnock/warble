#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A key code plus Carbon modifier mask, as used by `RegisterEventHotKey`.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var encoded: String { "\(keyCode):\(modifiers)" }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else {
            return nil
        }
        self.init(keyCode: code, modifiers: mods)
    }

    public var keyLabel: String { Self.keyLabels[keyCode] ?? "#\(keyCode)" }

    // CGEventFlags is Apple-only; Linux builds the rest for WarbleModelTests.
    #if canImport(CoreGraphics)
    /// The combo of `keyCode` with the modifiers among `flags`, which `NSEvent.ModifierFlags` shares the bits of.
    public init(keyCode: UInt32, eventFlags flags: CGEventFlags) {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= Self.command }
        if flags.contains(.maskShift) { modifiers |= Self.shift }
        if flags.contains(.maskAlternate) { modifiers |= Self.option }
        if flags.contains(.maskControl) { modifiers |= Self.control }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// The modifiers as event flags, which `NSEvent.ModifierFlags` shares the bits of.
    public var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & Self.command != 0 { flags.insert(.maskCommand) }
        if modifiers & Self.shift != 0 { flags.insert(.maskShift) }
        if modifiers & Self.option != 0 { flags.insert(.maskAlternate) }
        if modifiers & Self.control != 0 { flags.insert(.maskControl) }
        return flags
    }
    #endif

    public var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + keyLabel
    }

    // ANSI virtual key codes (kVK_*).
    static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 50: "`", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]
}
