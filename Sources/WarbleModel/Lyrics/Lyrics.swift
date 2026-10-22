import Foundation

/// A track's synced lyrics, parsed from LRC: lines like `[01:23.45] text`, sorted by when they start.
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// When the line starts, in seconds into the track.
        public var time: TimeInterval
        /// Empty for a gap, such as an instrumental break, where nothing shows.
        public var text: String

        public init(time: TimeInterval, text: String) {
            self.time = time
            self.text = text
        }
    }

    /// Sorted by `time`. Lines that start together keep the order of the file.
    public let lines: [Line]
    /// The indices in `lines` of the lines with words, so the lyrics card finds its lines without walking every gap.
    let sung: [Int]

    /// Parses LRC text, or returns `nil` when it has no timed lines, as with plain lyrics.
    ///
    /// A line can start with several timestamps, `[00:12.00][00:48.50] Chorus`, and is then repeated at each. Timestamps
    /// are `[mm:ss]`, with up to four digits of minutes and three of fraction after a `.` or `:`. `[offset:+500]` moves every line earlier by
    /// that many milliseconds, wherever it is in the file; a negative offset moves them later. Other tags (`[ar:]`,
    /// `[ti:]`, `[length:]` and the like), lines without a timestamp and enhanced LRC's word times (`<00:12.30>`) are
    /// dropped.
    public init?(lrc: String) {
        var timed: [(milliseconds: Int, text: String)] = []
        var offset = 0
        for row in lrc.split(whereSeparator: \.isNewline) {
            var rest = row.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
            var times: [Int] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = Self.milliseconds(tag) {
                    times.append(time)
                } else if let value = Self.offset(tag) {
                    offset = value
                } else {
                    break
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = Self.withoutWordTimes(rest).trimmingCharacters(in: .whitespaces)
            timed += times.map { ($0, text) }
        }
        guard !timed.isEmpty else { return nil }
        let lines = timed.enumerated()
            .sorted { ($0.element.milliseconds, $0.offset) < ($1.element.milliseconds, $1.offset) }
            .map { Line(time: TimeInterval(max($0.element.milliseconds - offset, 0)) / 1000, text: $0.element.text) }
        self.lines = lines
        sung = lines.indices.filter { !lines[$0].text.isEmpty }
    }

    /// The line showing at `position`: the last to start at or before it, or `nil` before the first line.
    public func line(at position: TimeInterval) -> Line? {
        let next = firstIndex(after: position)
        return next == 0 ? nil : lines[next - 1]
    }

    /// The index in `lines` of the line showing at `position`, or `nil` before the first line.
    func index(at position: TimeInterval) -> Int? {
        let next = firstIndex(after: position)
        return next == 0 ? nil : next - 1
    }

    /// When the line showing at `position` gives way to the next, or `nil` after the last line starts.
    public func nextChange(after position: TimeInterval) -> TimeInterval? {
        let next = firstIndex(after: position)
        return next < lines.count ? lines[next].time : nil
    }

    /// The index of the first line that starts after `position`, or `lines.count` when none does.
    private func firstIndex(after position: TimeInterval) -> Int {
        var (low, high) = (0, lines.count)
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// `mm:ss`, `mm:ss.f` up to `mm:ss.fff`, or the same with `:` before the fraction, in milliseconds.
    private static func milliseconds(_ tag: Substring) -> Int? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var seconds = parts[1]
        var fraction: Substring?
        if parts.count == 3 {
            fraction = parts[2]
        } else if let dot = seconds.firstIndex(of: ".") {
            fraction = seconds[seconds.index(after: dot)...]
            seconds = seconds[..<dot]
        }
        // Up to four digits of minutes, so a line anyone can edit on LRCLIB can't overflow the arithmetic below.
        guard parts[0].count <= 4, let minutes = digits(parts[0]), let whole = digits(seconds), seconds.count <= 2,
              fraction.map({ digits($0) != nil }) ?? true
        else { return nil }
        let thousandths = Int(String(((fraction ?? "") + "000").prefix(3)))!
        return (minutes * 60 + whole) * 1000 + thousandths
    }

    /// The milliseconds of an `offset:` tag, such as `offset:+500` or `offset: -250`, kept within a day either way.
    private static func offset(_ tag: Substring) -> Int? {
        guard let colon = tag.firstIndex(of: ":"),
              tag[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "offset"
        else { return nil }
        let day = 86_400_000
        return Int(tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces)).map { min(max($0, -day), day) }
    }

    private static func digits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) else { return nil }
        return Int(text)
    }

    /// `text` without enhanced LRC's word times, `<mm:ss.xx>`.
    private static func withoutWordTimes(_ text: Substring) -> String {
        var result = ""
        var rest = text
        while let open = rest.firstIndex(of: "<") {
            if let close = rest[open...].firstIndex(of: ">"), milliseconds(rest[rest.index(after: open)..<close]) != nil {
                result += rest[..<open]
                rest = rest[rest.index(after: close)...]
            } else {
                result += rest[...open]
                rest = rest[rest.index(after: open)...]
            }
        }
        return result + rest
    }
}
