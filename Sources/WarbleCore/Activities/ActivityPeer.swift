import Darwin
import Foundation
import Security
import WarbleModel

/// Works out who is on the other end of an activities connection, from the connection itself and never from what it sends.
public enum ActivityPeer {
    /// Bundle identifiers of interpreters that count as scripts even when they get past the bundle test, since what they run
    /// is a script whatever the interpreter is signed as.
    static let interpreters: Set<String> = ["org.python.python"]

    /// What the signature and the process say about a peer, before it's classified.
    struct Facts: Equatable {
        var executable: String
        /// Set only when the code signature checks out, as a signed app's team ID and signing identifier.
        var teamID: String?
        var signingIdentifier: String?
    }

    /// The sender at the other end of `fd`, identified once, at connect.
    public static func identify(_ fd: Int32, client: Int) -> ActivitySender {
        classify(facts(of: fd), client: client)
    }

    /// A signed app only if its executable is inside a top-level `.app` bundle and signed with a team ID. Everything else is a
    /// script, keyed by its executable's path. Scripts are a label for the reader and not a security boundary: a signed app's
    /// identity needs its signing key, so no script can pass as one.
    static func classify(_ facts: Facts, client: Int) -> ActivitySender {
        guard let teamID = facts.teamID, let signingIdentifier = facts.signingIdentifier,
              let app = topLevelApp(containing: facts.executable), !interpreters.contains(signingIdentifier)
        else {
            return ActivitySender(client: client, identifier: facts.executable, name: URL(fileURLWithPath: facts.executable).lastPathComponent)
        }
        return ActivitySender(
            client: client, identifier: "\(teamID).\(signingIdentifier)", name: displayName(of: app), bundleIdentifier: signingIdentifier
        )
    }

    /// The `.app` folder `executable` is the main executable of, when that app isn't inside another bundle.
    static func topLevelApp(containing executable: String) -> URL? {
        let parts = URL(fileURLWithPath: executable).pathComponents
        // .../Name.app/Contents/MacOS/Executable
        guard parts.count >= 4, parts[parts.count - 3] == "Contents", parts[parts.count - 2] == "MacOS",
              parts[parts.count - 4].hasSuffix(".app")
        else { return nil }
        let bundleSuffixes = [".app", ".framework", ".xpc", ".appex", ".bundle", ".plugin", ".kext"]
        let outside = parts[..<(parts.count - 4)]
        guard !outside.contains(where: { part in bundleSuffixes.contains { part.hasSuffix($0) } }) else { return nil }
        return URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The name Finder shows, from the app's own Info.plist, which the signature seals.
    static func displayName(of app: URL) -> String {
        let info = Bundle(url: app)?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? app.deletingPathExtension().lastPathComponent
    }

    private static func facts(of fd: Int32) -> Facts {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else {
            return Facts(executable: "unknown")
        }
        let pid = pid_t(token.val.5)
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = proc_pidpath(pid, &path, UInt32(path.count))
        let executable = count > 0 ? String(decoding: path[..<Int(count)].map { UInt8(bitPattern: $0) }, as: UTF8.self) : "unknown"
        let identity = signature(of: token)
        return Facts(executable: executable, teamID: identity?.teamID, signingIdentifier: identity?.identifier)
    }

    /// The team ID and signing identifier of the process `token` names, when its signature is valid, running and on disk.
    private static func signature(of token: audit_token_t) -> (teamID: String, identifier: String)? {
        var token = token
        let attributes = [kSecGuestAttributeAudit: Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let guest,
              // The running code, then the files on disk (the sealed Info.plist the name comes from).
              SecCodeCheckValidity(guest, [], nil) == errSecSuccess
        else { return nil }
        var code: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
        else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let team = information[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let identifier = information[kSecCodeInfoIdentifier as String] as? String, !identifier.isEmpty
        else { return nil }
        return (team, identifier)
    }
}
