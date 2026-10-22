import Foundation
import WarbleModel

/// The `warble` command line: `warble now` and the commands that do what the notch's buttons do. It ships inside the app as
/// `Contents/MacOS/warble-cli`, and asks the running app over its socket, which the app opens only while Settings ›
/// Developer › Allow the warble command is on. It never opens Warble itself.
@main
enum WarbleCLI {
    static func main() {
        let program = URL(fileURLWithPath: CommandLine.arguments.first ?? "warble").lastPathComponent
        let arguments = Array(CommandLine.arguments.dropFirst())
        // The command is called `warble` or `warble-dev` when linked, but `warble-cli` inside the app.
        let shown = program == "warble-cli" ? "warble" : program
        let command: WarbleCommand
        do {
            command = try WarbleCommand.parse(arguments)
        } catch {
            printError("\(shown): \(error.message)")
            if case .usage = error {
                printError(WarbleCommand.usage(nil, program: shown))
            }
            exit(error.exitCode)
        }
        switch command {
        case .version:
            let app = appBundle()
            let version = app?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
            print("Warble \(version)")
        case .help(let name):
            print(WarbleCommand.usage(name, program: shown))
        case .now(let json):
            do throws(RemoteCommandError) {
                guard let snapshot = try send(arguments) else {
                    throw .io("Warble answered without saying what's playing")
                }
                print(json ? snapshot.json : snapshot.text)
            } catch {
                fail(shown, error)
            }
        case .send:
            do throws(RemoteCommandError) {
                _ = try send(arguments)
            } catch {
                fail(shown, error)
            }
        }
    }

    private static func fail(_ program: String, _ error: RemoteCommandError) -> Never {
        printError("\(program): \(error.message)")
        exit(error.exitCode)
    }

    /// Asks the running app, and returns what it found for a `now`.
    private static func send(_ arguments: [String]) throws(RemoteCommandError) -> NowPlayingSnapshot? {
        let bundleIdentifier = appBundle()?.bundleIdentifier ?? fallbackBundleIdentifier
        guard let url = RemoteSocketPath.url(bundleIdentifier: bundleIdentifier) else {
            throw .unavailable("this command isn't inside a copy of Warble, so it can't tell which one to ask")
        }
        let line = try AgentClient.exchange(RemoteRequest(arguments: arguments).line, at: url)
        return try RemoteResponse.decode(line).result()
    }

    /// The app this executable is inside. `Bundle.main` finds it when run by its real path, but not through a symlink such
    /// as Homebrew's `warble`, so that path is resolved first.
    static func appBundle() -> Bundle? {
        if Bundle.main.bundleIdentifier != nil {
            return Bundle.main
        }
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }
        // Warble.app/Contents/MacOS/warble-cli
        let bundle = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        return bundle?.bundleIdentifier != nil ? bundle : nil
    }

    /// The dev build's, for a bare `.build/debug/WarbleCLI` with no app around it. `WARBLE_BUNDLE_ID` picks another.
    static var fallbackBundleIdentifier: String {
        ProcessInfo.processInfo.environment["WARBLE_BUNDLE_ID"] ?? "dev.lorcan.Warble.dev"
    }

    private static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
