import Foundation
import Testing
@testable import WarbleCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func span(_ title: String, daysAgo: Double = 0) -> ListenedSpan {
    ListenedSpan(start: now - daysAgo * 86400, seconds: 90, title: title, artist: "Artist")
}

private func temporaryFile() -> StatsFile {
    StatsFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("warble-stats-\(UUID().uuidString)/Stats.jsonl"))
}

@Test func spansAppendAndLoadInOrder() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try file.append(span("One"))
    try file.append(span("Two"))
    #expect(file.load(since: now - 86400 * 30) == [span("One"), span("Two")])
}

@Test func loadingFromNothingIsEmpty() {
    #expect(temporaryFile().load(since: .distantPast).isEmpty)
}

@Test func loadingDropsSpansOlderThanTheDateFromTheFile() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try file.append(span("Old", daysAgo: 40))
    try file.append(span("New", daysAgo: 2))
    #expect(file.load(since: now - 86400 * 30) == [span("New", daysAgo: 2)])
    #expect(file.load(since: .distantPast) == [span("New", daysAgo: 2)])
}

@Test func aBrokenLineIsSkipped() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try file.append(span("One"))
    let handle = try FileHandle(forWritingTo: file.url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("not json\n".utf8))
    try handle.close()
    try file.append(span("Two"))
    #expect(file.load(since: .distantPast).map(\.title) == ["One", "Two"])
}

@Test func clearingDeletesTheFileAndNeedsNoFile() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try file.clear()
    try file.append(span("One"))
    try file.clear()
    #expect(file.load(since: .distantPast).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.url.path))
}
