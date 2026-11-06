import AppKit
import Foundation
import WarbleModel

/// Reads and sets the `favorited` of the song Music is playing, with the scripts in `Favourite`. They run on
/// `ScriptSource`'s queue, one at a time and off the main thread, so a set and a read never reach Music out of order.
/// Music is scripted only while it runs, since a script that names an app opens it, and the first script asks for
/// Automation permission for Music if Warble doesn't have it yet.
public struct ScriptedFavourites: MusicFavourites {
    public init() {}

    public func isFavourite(title: String) async -> Bool? {
        await run(Favourite.readScript(title: title))
    }

    public func setFavourite(_ favourited: Bool, title: String) async -> Bool? {
        await run(Favourite.setScript(favourited, title: title))
    }

    /// The Boolean the script returns, or `nil` when Music isn't running, the script fails or it returns anything else.
    private func run(_ source: String) async -> Bool? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Favourite.music).isEmpty else { return nil }
        let value = await ScriptSource.execute(source) { ScriptValue($0) }.result
        guard case .bool(let favourited)? = value else { return nil }
        return favourited
    }
}
