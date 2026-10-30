import Foundation

/// Which displays show a full-screen app, read from the window server's list of each display's Spaces.
public enum FullScreenDisplays {
    /// The window server's type for a full-screen app's Space; a desktop's is 0.
    static let fullScreenType = 4

    /// The displays whose current Space is a full-screen app's, by display UUID. With Displays have separate Spaces off,
    /// every display shares one Space, which the window server names "Main", so it stands for `allDisplays`.
    public static func from(spaces: [[String: Any]], allDisplays: [String]) -> Set<String> {
        var displays: Set<String> = []
        for display in spaces {
            guard let current = display["Current Space"] as? [String: Any], current["type"] as? Int == fullScreenType,
                  let id = display["Display Identifier"] as? String
            else { continue }
            if id == "Main" {
                displays.formUnion(allDisplays)
            } else {
                displays.insert(id)
            }
        }
        return displays
    }
}
