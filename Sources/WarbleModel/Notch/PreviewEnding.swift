import Foundation

/// How the Settings preview's made-up song ends once it pauses, so the pause and external-display settings each change
/// what the preview shows.
public enum PreviewEnding: Equatable, Sendable {
    /// The paused song stays.
    case paused
    /// The song goes and an empty notch stays.
    case emptyNotch
    /// The song goes and so does the notch, leaving the bare screen.
    case bareScreen

    /// How long the paused song shows before it ends. The same for 10 seconds and 1 minute, since a shortened wait would
    /// suggest a shorter one than the setting gives.
    public static let beat: Duration = .milliseconds(1500)

    public init(pauseDelay: PauseDelay, visibility: VirtualNotchVisibility) {
        switch (pauseDelay, visibility) {
        case (_, .off): self = .bareScreen
        case (.always, _): self = .paused
        case (_, .always): self = .emptyNotch
        case (_, .whenPlaying): self = .bareScreen
        }
    }
}
