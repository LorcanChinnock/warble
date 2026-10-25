import AppKit
import SwiftUI
import WarbleCore

/// The sender's own icon, with the activity's symbol as a small badge on it. The wing always draws the sender's real icon,
/// the signed app's or a generic mark for a script, so no sender can make wings that look like another app's. A symbol
/// Warble can't draw is left off.
struct ActivityIconView: View {
    let owner: ActivityOwner
    let icon: ActivityIcon?
    let size: CGFloat
    @State private var appIcon: NSImage?

    var body: some View {
        Group {
            if let appIcon {
                Image(nsImage: appIcon).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                    .fill(Color(white: 0.15))
                    .overlay {
                        Image(systemName: owner.isScript ? "terminal.fill" : "app.fill")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(Native.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let icon, Self.draws(icon.symbol) {
                Image(systemName: icon.symbol)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(icon.tint.color)
                    .frame(width: size * 0.55, height: size * 0.55)
                    .background(Circle().fill(.black))
                    .offset(x: size * 0.15, y: size * 0.15)
            }
        }
        .task(id: owner.bundleIdentifier) {
            guard !owner.isScript, let bundleIdentifier = owner.bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else {
                appIcon = nil
                return
            }
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        .accessibilityHidden(true)
    }

    /// Whether SF Symbols has `name`, which the model can't tell.
    static func draws(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

extension ActivityTint {
    var color: Color {
        switch self {
        case .white: .white
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        }
    }
}

extension ActivityOwner {
    /// What the card says above the title: the app's name, or "Script: <name>".
    var displayName: Text {
        isScript ? Text("Script: \(name)") : Text(verbatim: name)
    }

    /// What VoiceOver reads for an activity: the app's name, then the title.
    func spoken(_ title: String) -> Text {
        displayName + Text(verbatim: ": \(title)")
    }
}
