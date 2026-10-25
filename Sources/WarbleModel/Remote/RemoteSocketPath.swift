import Foundation

/// Where the running app listens for the `warble` command, which the app and the command both work out the same way.
public enum RemoteSocketPath {
    /// `agent.sock` in the app's folder in Application Support, one for each bundle identifier, so Warble and WarbleDev
    /// never answer each other's commands.
    public static func url(bundleIdentifier: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("agent.sock")
    }

    /// What `warble` says when nothing answers at the socket.
    public static let nothingAnswering = "Warble isn't answering the command line. Open Warble, and turn on Settings › Developer › Allow the warble command."
}
