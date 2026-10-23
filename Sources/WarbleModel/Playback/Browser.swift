import Foundation

/// A browser that can tell Warble which page its front tab shows, so the idle card can reopen a track that played in a
/// tab. Only those with AppleScript tab support, and only read when the user turns on the setting.
public enum Browser: String, CaseIterable, Sendable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case brave = "com.brave.Browser"
    case edge = "com.microsoft.edgemac"
    case arc = "company.thebrowser.Browser"
    case vivaldi = "com.vivaldi.Vivaldi"

    public var bundleIdentifier: String { rawValue }

    /// Returns `{address, title}` for the front window's current tab, or `missing value` when it has no window. It's
    /// sent by bundle ID, only to a browser that's running, since a script that names an app opens it.
    public var frontTabScript: String {
        let tab = self == .safari ? "current tab" : "active tab"
        return """
        with timeout of 5 seconds
            tell application id "\(bundleIdentifier)"
                if (count of windows) is 0 then return missing value
                set theTab to \(tab) of front window
                return {URL of theTab, \(self == .safari ? "name" : "title") of theTab}
            end tell
        end timeout
        """
    }

    /// The address to reopen `trackTitle` at, from the front tab's `address` and `tabTitle`. A tab that doesn't show the
    /// track by name is some other page, because the user moved on before Warble looked, so it gives nothing. Only a web
    /// address, since the track reopens with the system's handler for it.
    public static func link(address: String, tabTitle: String, trackTitle: String) -> URL? {
        guard !trackTitle.isEmpty, tabTitle.localizedCaseInsensitiveContains(trackTitle),
              let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }
}
