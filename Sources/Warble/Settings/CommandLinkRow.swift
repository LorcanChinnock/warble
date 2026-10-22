import AppKit
import SwiftUI
import WarbleCore

/// Installs or removes the `warble` command for a copy of Warble that Homebrew didn't install: a link in `/usr/local/bin`
/// to this app's `warble-cli`, made with an administrator's password.
struct CommandLinkRow: View {
    @State private var status = CommandLink.Status.missing
    @State private var working = false
    /// What went wrong the last time, shown in place of the usual note until the next try.
    @State private var failure: String?
    private let name = CommandLink.name(bundleID: Bundle.main.bundleIdentifier)
    private let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(CommandLink.executableName)").path
    private var link: String { (CommandLink.folder as NSString).appendingPathComponent(name) }

    var body: some View {
        LabeledContent {
            switch status {
            case .missing:
                button("Install", CommandLink.installScript(name: name, cli: cli))
            case .linked:
                button("Uninstall", CommandLink.uninstallScript(name: name))
            case .stale:
                button("Reinstall", CommandLink.installScript(name: name, cli: cli))
            case .homebrew, .taken:
                EmptyView()
            }
        } label: {
            Text("Use \(name) in Terminal")
            Text(subtitle)
        }
        .accessibilityElement(children: .combine)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var subtitle: String {
        if let failure { return String(localized: "Couldn't change the \(name) command: \(failure)") }
        return switch status {
        case .missing: String(localized: "Installing asks for your password once.")
        case .linked: String(localized: "Installed at \(link). It updates with Warble.")
        case .homebrew: String(localized: "Installed by Homebrew. It updates with Warble.")
        case .stale: String(localized: "Points to a copy of Warble that has moved. Reinstall to fix it.")
        case .taken: String(localized: "Another program uses \(link). Run \(cli) instead.")
        }
    }

    private func button(_ title: LocalizedStringResource, _ script: String) -> some View {
        Button(String(localized: title)) { run(script) }
            .disabled(working)
    }

    private func refresh() {
        status = CommandLink.status(name: name, cli: cli)
    }

    /// Runs `script` through `osascript`, whose password prompt would stall the main thread if run in process.
    private func run(_ script: String) {
        working = true
        failure = nil
        Task {
            let problem = await Task.detached { () -> String? in
                let process = Process()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    return error.localizedDescription
                }
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                // -128 is the user cancelling the password prompt, which needs no message.
                guard process.terminationStatus != 0, !message.contains("(-128)") else {
                    return nil
                }
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
            working = false
            refresh()
            failure = problem
        }
    }
}
