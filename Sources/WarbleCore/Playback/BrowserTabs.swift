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
        script(bundleIdentifier: bundleIdentifier, title: title, otherwise: "false") { select in
            """
            \(select)
            set index of w to 1
            activate
            return true
            """
        }
    }

    /// The script that returns the address of the tab titled `title`, or an empty string when no tab matches.
    public static func urlScript(bundleIdentifier: String, title: String) -> String? {
        script(bundleIdentifier: bundleIdentifier, title: title, otherwise: "\"\"") { _ in "return URL of t" }
    }

    /// Runs `found` with the statement that selects the tab, in the first tab whose title contains `title`.
    private static func script(bundleIdentifier: String, title: String, otherwise: String, found: (String) -> String) -> String? {
        let quoted = "\"" + title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        let select: String, property: String
        if bundleIdentifier == safari {
            (select, property) = ("set current tab of w to t", "name")
        } else if chromium.contains(bundleIdentifier) {
            (select, property) = ("set active tab index of w to i", "title")
        } else {
            return nil
        }
        return """
        with timeout of 5 seconds
            tell application id "\(bundleIdentifier)"
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if (\(property) of t as text) contains \(quoted) then
                            \(found(select).replacingOccurrences(of: "\n", with: "\n                    "))
                        end if
                    end repeat
                end repeat
                return \(otherwise)
            end tell
        end timeout
        """
    }

    /// Selects the tab and returns true, or returns false when the script fails, the user has turned Automation off, or no
    /// tab matches, so the caller can open the browser instead.
    public static func focus(bundleIdentifier: String, title: String) async -> Bool {
        guard let source = script(bundleIdentifier: bundleIdentifier, title: title) else { return false }
        return await run(source)?.booleanValue ?? false
    }

    /// The address of the tab titled `title`, or `nil` when the script fails, Automation is off or no tab matches.
    public static func url(bundleIdentifier: String, title: String) async -> URL? {
        guard let source = urlScript(bundleIdentifier: bundleIdentifier, title: title) else { return nil }
        return await run(source)?.stringValue.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// Runs `source` off the main thread, logging a failure.
    static func run(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    log.error("Script failed: \(error[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
                }
                continuation.resume(returning: error == nil ? result : nil)
            }
        }
    }
}
