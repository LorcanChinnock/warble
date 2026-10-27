import AppKit
import Foundation
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "tabs")

/// Brings the tab that's playing to the front, in the browsers that script it. The adapter says which browser is
/// playing but not which tab, so the tab is the one whose title contains the track's title (YouTube adds " - YouTube").
/// The first click asks for Automation permission for that browser; nothing runs until a click.
public enum BrowserTabs {
    private static let safari = "com.apple.Safari"
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    /// The script that selects the tab titled `title`, or `nil` when `bundleIdentifier` isn't a browser Warble can script.
    public static func script(bundleIdentifier: String, title: String) -> String? {
        let quoted = "\"" + title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        let select: String
        if bundleIdentifier == safari {
            select = "set current tab of w to t"
        } else if chromium.contains(bundleIdentifier) {
            select = "set active tab index of w to i"
        } else {
            return nil
        }
        return """
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if (name of t as text) contains \(quoted) then
                        \(select)
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
    }

    /// Selects the tab and returns true, or returns false when the script fails, the user has turned Automation off, or no
    /// tab matches, so the caller can open the browser instead.
    public static func focus(bundleIdentifier: String, title: String) async -> Bool {
        guard let source = script(bundleIdentifier: bundleIdentifier, title: title) else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    log.error("Tab script failed: \(error[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
                }
                continuation.resume(returning: result?.booleanValue ?? false)
            }
        }
    }
}
