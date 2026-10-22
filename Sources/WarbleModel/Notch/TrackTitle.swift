import Foundation

/// The title a virtual notch draws in its middle: what to cut from it and how much of it fits. Pure, with the view
/// measuring the widths, so it runs on Linux like the rest of the model.
public enum TrackTitle {
    /// What fits in the middle of the notch.
    public enum Line: Equatable, Sendable {
        /// "Title — Artist", all of it.
        case titleAndArtist(String)
        /// The title alone, all of it.
        case title(String)
        /// The title, which is too long: its start shows and its end fades out.
        case faded(String)

        public var text: String {
            switch self {
            case .titleAndArtist(let text), .title(let text), .faded(let text): text
            }
        }

        /// Whether the text is wider than the notch, so it can scroll to its end.
        public var isCut: Bool {
            if case .faded = self { true } else { false }
        }
    }

    /// The first word of a bracketed tag that is only extra detail about the recording.
    private static let tagWords: Set<String> = [
        "feat", "ft", "featuring", "live", "official", "remaster", "remastered", "mono", "stereo", "lyrics", "lyric",
        "audio", "video", "hd", "hq", "deluxe", "bonus", "explicit", "clean", "single", "radio",
    ]
    /// What a tag after a dash starts with. Stricter than the brackets, since a dash often joins an artist to a title.
    private static let dashTags = [
        "live at", "live in", "live from", "live on", "mono", "stereo", "single version", "radio edit", "radio mix",
        "deluxe", "bonus track",
    ]
    private static let dashes = [" - ", " – ", " — "]

    /// `title` without the tags a track's name collects at its end, such as "- Remastered 2009", "(feat. …)",
    /// "[Live at …]" and "(Official Video)", so it fits in less room. A title that is only a tag is left as it is.
    public static func trimmed(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespaces)
        while let shorter = withoutLastTag(result), !shorter.isEmpty {
            result = shorter
        }
        return result
    }

    /// What of `title` and `artist` fits in `width`, given `measure`, the width `text` takes in the notch's font. Both
    /// if they fit, else the title, else the title faded.
    public static func line(title: String, artist: String?, width: Double, measure: (String) -> Double) -> Line {
        let title = trimmed(title)
        if let artist = artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty {
            let both = "\(title) — \(artist)"
            if measure(both) <= width {
                return .titleAndArtist(both)
            }
        }
        return measure(title) <= width ? .title(title) : .faded(title)
    }

    private static func withoutLastTag(_ title: String) -> String? {
        if let close = title.last, let open = ["(": ")", "[": "]"].first(where: { $0.value == String(close) })?.key,
           let start = title.lastIndex(of: Character(open))
        {
            let body = title[title.index(after: start)..<title.index(before: title.endIndex)]
            return isBracketTag(body) ? String(title[..<start]).trimmingCharacters(in: .whitespaces) : nil
        }
        for dash in dashes {
            if let range = title.range(of: dash, options: .backwards) {
                let tail = title[range.upperBound...]
                if isDashTag(tail) {
                    return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    private static func isBracketTag(_ body: Substring) -> Bool {
        let lower = body.lowercased()
        let first = lower.split { !$0.isLetter }.first.map(String.init)
        return lower.contains("remaster") || first.map(tagWords.contains) == true
    }

    private static func isDashTag(_ tail: Substring) -> Bool {
        let lower = tail.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.contains("remaster") || dashTags.contains { lower == $0 || lower.hasPrefix($0 + " ") }
    }
}
