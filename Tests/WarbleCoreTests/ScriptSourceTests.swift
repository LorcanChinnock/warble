import Foundation
import Testing
import WarbleCore

// These build the descriptors a script returns rather than run one, which would send Music or Spotify an Apple Event.

/// AppleScript's `missing value`, the type 'msng', which Swift doesn't import as `cMissingValue`.
private var missingValue: NSAppleEventDescriptor { NSAppleEventDescriptor(typeCode: 0x6D73_6E67) }

@Test func aScriptsTextNumbersAndBooleansAreRead() {
    #expect(ScriptValue(NSAppleEventDescriptor(string: "Song")) == .text("Song"))
    #expect(ScriptValue(NSAppleEventDescriptor(double: 61.5)) == .number(61.5))
    #expect(ScriptValue(NSAppleEventDescriptor(int32: 240)) == .number(240))
    #expect(ScriptValue(NSAppleEventDescriptor(boolean: true)) == .bool(true))
}

@Test func aMissingValueIsMissing() {
    #expect(ScriptValue(missingValue) == .missing)
    #expect(ScriptValue(nil) == .missing)
}

@Test func aListReadsAsAStateReport() throws {
    let list = NSAppleEventDescriptor.list()
    let items = [
        NSAppleEventDescriptor(string: "playing"), NSAppleEventDescriptor(string: "Song"), NSAppleEventDescriptor(string: "Artist"),
        NSAppleEventDescriptor(string: "Album"), NSAppleEventDescriptor(double: 240), NSAppleEventDescriptor(double: 30),
        NSAppleEventDescriptor(string: "off"), NSAppleEventDescriptor(string: "all"), missingValue,
    ]
    for (index, item) in items.enumerated() {
        list.insert(item, at: index + 1)
    }
    let report = (0..<list.numberOfItems).map { ScriptValue(list.atIndex($0 + 1)) }
    let state = try #require(PlaybackState(player: .music, report: report, at: .now))
    #expect(state.title == "Song")
    #expect(state.duration == 240)
    #expect(state.repeatMode == .all)
}

@Test func artworkIsTheBytesReturnedAndMissingValueIsNone() {
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    #expect(NSAppleEventDescriptor(descriptorType: 0x504E_4766, data: png)?.artworkData == png) // 'PNGf'
    #expect(missingValue.artworkData == nil)
}
