import Foundation

/// A release's notes as the update window lists them: one entry per version, newest first, each with its groups of
/// changes. The release workflow embeds the last few releases' notes in the feed, as release-please wrote them, so the
/// window can show every version since the installed one.
public struct ReleaseNotes: Equatable, Sendable {
    public struct Version: Equatable, Sendable {
        /// The version from its heading, or nil for notes with no version headings.
        public var version: String?
        public var groups: [Group]

        public init(version: String?, groups: [Group]) {
            self.version = version
            self.groups = groups
        }
    }

    public struct Group: Equatable, Sendable {
        public var kind: Kind
        public var items: [String]

        public init(kind: Kind, items: [String]) {
            self.kind = kind
            self.items = items
        }
    }

    /// What a group of changes is, from release-please's heading. WarbleCore names them.
    public enum Kind: Equatable, Sendable {
        /// "Features", shown as New.
        case new
        /// "Bug Fixes", shown as Fixed.
        case fixed
        /// "Performance Improvements", shown as Faster.
        case faster
        /// Any other heading, shown as it is.
        case other(String)
        /// Items before any heading, shown without one.
        case untitled
    }

    public enum Format: Sendable {
        case markdown
        case html
        case plainText
    }

    public var versions: [Version]

    public init(versions: [Version]) {
        self.versions = versions
    }

    public var isEmpty: Bool {
        versions.allSatisfy { $0.groups.isEmpty }
    }

    /// The format Sparkle gives for an item's notes (`sparkle:format`): "markdown", "plain-text", or HTML by default.
    public static func format(sparkle: String?) -> Format {
        switch sparkle {
        case "markdown": .markdown
        case "plain-text": .plainText
        default: .html
        }
    }

    /// The format of notes from a file, from its MIME type or the end of its name, as Sparkle chooses.
    public static func format(mimeType: String?, pathExtension: String?) -> Format {
        let mime = mimeType?.lowercased() ?? ""
        let ext = pathExtension?.lowercased() ?? ""
        if mime == "text/markdown" || ext == "md" || ext == "markdown" {
            return .markdown
        }
        if mime == "text/plain" || ext == "txt" {
            return .plainText
        }
        return .html
    }

    /// Reads notes. In Markdown and plain text, a `##` heading starts a version, a `###` heading starts a group, and each
    /// bullet is one change. Other text is left out, so notes with no list have no changes. HTML gives its list items as
    /// one untitled group.
    public init(_ notes: String, format: Format) {
        switch format {
        case .html:
            let items = Self.htmlItems(notes).map(Self.clean).filter { !$0.isEmpty }
            versions = items.isEmpty ? [] : [Version(version: nil, groups: [Group(kind: .untitled, items: items)])]
        case .markdown, .plainText:
            versions = Self.markdownVersions(notes)
        }
    }

    /// The versions newer than `installed`. The notes run newest first, so it keeps everything above the installed
    /// version's heading. When that heading isn't there, because the installed version is older than every version in
    /// the notes, it keeps them all.
    public func since(_ installed: String) -> ReleaseNotes {
        let installed = Self.normalised(installed)
        guard let index = versions.firstIndex(where: { $0.version.map(Self.normalised) == installed }) else {
            return self
        }
        return ReleaseNotes(versions: Array(versions[..<index]))
    }

    // MARK: Reading

    private static func markdownVersions(_ notes: String) -> [Version] {
        var versions: [Version] = []
        var version = Version(version: nil, groups: [])
        var group: Group?

        func endGroup() {
            if let group, !group.items.isEmpty {
                version.groups.append(group)
            }
            group = nil
        }
        func endVersion() {
            endGroup()
            if !version.groups.isEmpty {
                versions.append(version)
            }
        }

        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = heading(trimmed, level: 2) {
                endVersion()
                version = Version(version: versionName(heading), groups: [])
            } else if let heading = heading(trimmed, level: 3) {
                endGroup()
                group = Group(kind: kind(heading), items: [])
            } else if let item = bulletText(trimmed).map(clean), !item.isEmpty {
                if group == nil {
                    group = Group(kind: .untitled, items: [])
                }
                group?.items.append(item)
            }
        }
        endVersion()
        return versions
    }

    /// The text of a heading at exactly `level`: "## 0.2.0" is level 2, and "### Features" isn't.
    private static func heading(_ line: String, level: Int) -> String? {
        let marker = String(repeating: "#", count: level) + " "
        guard line.hasPrefix(marker) else {
            return nil
        }
        return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }

    /// The version in a release-please heading, "[0.2.0](https://…/compare/…) (2026-11-06)", or the heading's first word.
    private static func versionName(_ heading: String) -> String? {
        var text = heading
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: text.startIndex)..<close])
        }
        return text.split(separator: " ").first.map(String.init)
    }

    private static func kind(_ heading: String) -> Kind {
        switch heading.lowercased() {
        case "features": .new
        case "bug fixes": .fixed
        case "performance improvements": .faster
        default: .other(heading)
        }
    }

    private static func normalised(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["* ", "- ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func htmlItems(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<li[^>]*>(.*?)</li>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { decodeEntities(replacing("<[^>]+>", in: String(html[$0]), with: "")) }
        }
    }

    /// One change as a plain sentence: without the links to issues and commits that release-please adds, without its
    /// bold scope ("**notch:** "), and starting with a capital.
    private static func clean(_ item: String) -> String {
        var text = item
        // [text](url) becomes text.
        text = replacing(#"\[([^\]]*)\]\([^)]*\)"#, in: text, with: "$1")
        // release-please ends each line with the issue and the commit: (#407) (d8d6a10).
        text = replacing(#"(\s*\((#\d+|[0-9a-f]{7,40})(,\s*(#\d+|[0-9a-f]{7,40}))*\))+\s*$"#, in: text, with: "")
        // A bold scope at the start: **notch:** click…
        text = replacing(#"^\*\*[^*]+:\*\*\s*"#, in: text, with: "")
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        text = replacing(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespaces)
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    private static func decodeEntities(_ text: String) -> String {
        // &amp; goes last, so "&amp;lt;" becomes "&lt;" rather than "<".
        let entities = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")]
        return entities.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
