/// The face the notch sets the title in, which Settings chooses. The artist and album stay in the system font so the
/// line that names the song reads apart from them.
public enum NotchFont: String, CaseIterable, Sendable {
    case system
    case rounded
    case serif
    case monospaced
}
