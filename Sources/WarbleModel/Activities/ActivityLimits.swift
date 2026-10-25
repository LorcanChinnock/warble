import Foundation

/// What a sender may ask for. `ActivityRequest` refuses anything over, and `ActivityState` enforces the counts again, so
/// an action that gets past the handler can't break a rule.
public enum ActivityLimits {
    /// Activities shown at once across all apps, and for one connection.
    public static let activities = 3
    public static let perConnection = 2
    /// Lines a connection may send in a second.
    public static let linesPerSecond = 20
    /// The longest line, in bytes.
    public static let lineBytes = 4096

    public static let idBytes = 64
    public static let title = 60
    public static let detail = 100
    public static let badge = 8
    public static let from = 30
    public static let buttons = 2
    public static let buttonIDBytes = 32
    public static let buttonLabel = 16
    public static let symbolBytes = 64

    /// How long an activity lasts when `lasts` isn't given, and the most it may ask for, in seconds.
    public static let defaultLasts: TimeInterval = 3600
    public static let lasts: ClosedRange<TimeInterval> = 1...43200
}
