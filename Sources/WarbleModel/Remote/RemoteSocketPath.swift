import Foundation

/// Where the running app listens for the `warble` command, which the app and the command both work out the same way.
public enum RemoteSocketPath {
    /// `agent.sock` in the app's folder in Application Support, one for each bundle identifier, so Warble and WarbleDev
    /// never answer each other's commands.
    public static func url(bundleIdentifier: String) -> URL? {
        folder(bundleIdentifier: bundleIdentifier)?.appendingPathComponent("agent.sock")
    }

    /// `activities.sock` next to it, which other apps show activities in the notch over while Settings › Activities is on.
    public static func activitiesURL(bundleIdentifier: String) -> URL? {
        folder(bundleIdentifier: bundleIdentifier)?.appendingPathComponent("activities.sock")
    }

    private static func folder(bundleIdentifier: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// What `warble` says when nothing answers at the socket.
    public static let nothingAnswering = "Warble isn't answering the command line. Open Warble, and turn on Settings › Developer › Allow the warble command."
}
