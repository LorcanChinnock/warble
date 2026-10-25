import Foundation
import Testing
@testable import WarbleModel

private func decode(_ json: String, isScript: Bool = false) throws(ActivityError) -> ActivityRequest {
    try ActivityRequest.decode(Data(json.utf8), isScript: isScript)
}

/// The message a line is refused with, or `nil` when it's taken.
private func refusal(_ json: String, isScript: Bool = false) -> String? {
    do {
        _ = try decode(json, isScript: isScript)
        return nil
    } catch {
        return error.message
    }
}

private func draft(_ json: String, isScript: Bool = false) throws -> ActivityDraft {
    guard case .start(let draft) = try decode(json, isScript: isScript).operation else {
        throw ActivityError("not a start")
    }
    return draft
}

private func patch(_ json: String) throws -> ActivityPatch {
    guard case .update(_, let patch) = try decode(json).operation else {
        throw ActivityError("not an update")
    }
    return patch
}

private let minimal = #"{"v":1,"op":"start","id":"recording","title":"Recording"}"#

@Test func aStartWithOnlyATitleTakesTheDefaults() throws {
    let draft = try draft(minimal)
    #expect(draft.id == "recording")
    #expect(draft.title == "Recording")
    #expect(draft.lasts == 3600)
    #expect(draft.priority == .normal)
    #expect(draft.buttons.isEmpty)
    #expect(draft.detail == nil && draft.badge == nil && draft.icon == nil && draft.clock == nil)
}

@Test func aStartWithEveryFieldKeepsThemAll() throws {
    let draft = try draft("""
    {"v":1,"op":"start","id":"recording","title":"Recording Display 1","detail":"Saves to Desktop","badge":"REC",
     "icon":{"symbol":"record.circle","tint":"red"},"clock":{"since":1766592000.0},
     "buttons":[{"id":"stop","label":"Stop","symbol":"stop.fill"}],"priority":"high","lasts":120}
    """)
    #expect(draft.detail == "Saves to Desktop")
    #expect(draft.badge == "REC")
    #expect(draft.icon == ActivityIcon(symbol: "record.circle", tint: .red))
    #expect(draft.clock == .since(Date(timeIntervalSince1970: 1766592000)))
    #expect(draft.buttons == [ActivityButton(id: "stop", label: "Stop", symbol: "stop.fill")])
    #expect(draft.priority == .high)
    #expect(draft.lasts == 120)
}

@Test func anUntintedIconIsWhiteAndAClockCanCountDown() throws {
    let draft = try draft(#"{"v":1,"op":"start","id":"a","title":"T","icon":{"symbol":"timer"},"clock":{"until":100}}"#)
    #expect(draft.icon?.tint == .white)
    #expect(draft.clock == .until(Date(timeIntervalSince1970: 100)))
}

@Test func nullOnAStartIsTheSameAsLeavingTheFieldOut() throws {
    let draft = try draft(#"{"v":1,"op":"start","id":"a","title":"T","detail":null,"clock":null,"lasts":null}"#)
    #expect(draft.detail == nil && draft.clock == nil)
    #expect(draft.lasts == 3600)
}

@Test func updateAndEndNameTheActivityTheyAreFor() throws {
    let update = try decode(#"{"v":1,"op":"update","id":"recording","detail":"Paused"}"#)
    #expect(update.name == "update" && update.id == "recording")
    let end = try decode(#"{"v":1,"op":"end","id":"recording"}"#)
    #expect(end.operation == .end(id: "recording"))
    #expect(end.name == "end")
}

// MARK: The line

@Test func aLineThatIsntJSONIsRefused() {
    #expect(refusal("not json") == "the line isn't a JSON object")
    #expect(refusal("[1,2]") == "the line isn't a JSON object")
}

@Test func aLineOverFourKilobytesIsRefused() {
    let long = #"{"v":1,"op":"end","id":"a","pad":""# + String(repeating: "x", count: 4096) + #""}"#
    #expect(refusal(long)?.hasPrefix("the line is") == true)
}

@Test func anotherVersionIsRefusedNamingTheOneWarbleSpeaks() {
    #expect(refusal(#"{"v":2,"op":"end","id":"a"}"#)?.contains("only version 1") == true)
    #expect(refusal(#"{"op":"end","id":"a"}"#)?.contains("only version 1") == true)
}

@Test func anUnknownOrMissingOpIsRefused() {
    #expect(refusal(#"{"v":1,"id":"a"}"#) == "op is missing; it is start, update or end")
    #expect(refusal(#"{"v":1,"op":"pause","id":"a"}"#) == #"op "pause" isn't one Warble knows; it is start, update or end"#)
}

@Test func aRefusalNamesTheOpOnceItIsKnown() {
    do {
        _ = try decode(#"{"v":1,"op":"start","id":"a"}"#)
        Issue.record("took a start with no title")
    } catch {
        #expect(error.operation == "start")
        #expect(error.message == "title is missing")
    }
}

// MARK: Limits

@Test func theIDIsRequiredAndAtMostSixtyFourBytes() {
    #expect(refusal(#"{"v":1,"op":"end"}"#) == "id is missing")
    #expect(refusal(#"{"v":1,"op":"end","id":""}"#) == "id is empty")
    #expect(refusal(#"{"v":1,"op":"end","id":"\#(String(repeating: "a", count: 64))"}"#) == nil)
    #expect(refusal(#"{"v":1,"op":"end","id":"\#(String(repeating: "a", count: 65))"}"#) == "id is 65 bytes; the most is 64")
}

@Test func theTitleIsRequiredAndAtMostSixtyCharacters() {
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"\#(String(repeating: "t", count: 60))"}"#) == nil)
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"\#(String(repeating: "t", count: 74))"}"#) == "title is 74 characters; the most is 60")
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":""}"#) == "title is empty")
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":4}"#) == "title must be text")
}

@Test func aLongStringIsRefusedNotCut() {
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","detail":"\#(String(repeating: "d", count: 101))"}"#) == "detail is 101 characters; the most is 100")
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","badge":"123456789"}"#) == "badge is 9 characters; the most is 8")
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","badge":"12345678"}"#) == nil)
}

@Test func charactersAreCountedNotBytes() {
    // Sixty emoji are 240 bytes but 60 characters.
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"\#(String(repeating: "🔴", count: 60))"}"#) == nil)
}

@Test func theSymbolHasOnlyLowercaseLettersDigitsAndDots() {
    let start = #"{"v":1,"op":"start","id":"a","title":"T","icon":{"symbol":"#
    #expect(refusal(start + #""record.circle.fill"}}"#) == nil)
    #expect(refusal(start + #""Record Circle"}}"#)?.contains("only lowercase letters, digits and dots") == true)
    #expect(refusal(start + #""\#(String(repeating: "a", count: 65))"}}"#) == "icon symbol is 65 bytes; the most is 64")
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","icon":{}}"#) == "icon needs a symbol")
}

@Test func anUnknownTintNamesTheOnesThatExist() {
    let message = refusal(#"{"v":1,"op":"start","id":"a","title":"T","icon":{"symbol":"x","tint":"pink"}}"#)
    #expect(message == "icon tint isn't one Warble draws; it is white, red, orange, yellow, green or blue")
}

@Test func anIconFieldWarbleDoesntKnowIsRefusedSoNoImageCanBeSent() {
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","icon":{"symbol":"x","image":"AAAA"}}"#)?.contains("icon has no image") == true)
}

@Test func aClockHasSinceOrUntilAndNotBoth() {
    let start = #"{"v":1,"op":"start","id":"a","title":"T","clock":"#
    #expect(refusal(start + #"{"since":1}}"#) == nil)
    #expect(refusal(start + #"{}}"#) == "clock needs since or until, and only one of them")
    #expect(refusal(start + #"{"since":1,"until":2}}"#) == "clock needs since or until, and only one of them")
    #expect(refusal(start + #"{"since":"now"}}"#) == "clock since must be a number of seconds since 1970, up to the year 2100")
    // A date SwiftUI's timer can't draw would run its range backwards, so it's refused here.
    #expect(refusal(start + #"{"since":1e11}}"#) != nil)
    #expect(refusal(start + #"{"until":-5}}"#) != nil)
}

@Test func anActivityHasTwoButtonsAtMost() {
    func buttons(_ ids: String...) -> String {
        let list = ids.map { #"{"id":"\#($0)","label":"Go"}"# }.joined(separator: ",")
        return #"{"v":1,"op":"start","id":"a","title":"T","buttons":["# + list + "]}"
    }
    #expect(refusal(buttons("a", "b")) == nil)
    #expect(refusal(buttons("a", "b", "c")) == "buttons has 3; an activity can have 2 at most")
    #expect(refusal(buttons("a", "a")) == #"two buttons share the id "a""#)
}

@Test func aButtonsIDAndLabelAreCheckedAgainstTheirLimits() {
    let start = #"{"v":1,"op":"start","id":"a","title":"T","buttons":[{"#
    #expect(refusal(start + #""label":"Go"}]}"#) == "a button needs an id")
    #expect(refusal(start + #""id":"x"}]}"#) == "a button needs a label")
    #expect(refusal(start + #""id":"\#(String(repeating: "i", count: 33))","label":"Go"}]}"#) == "button id is 33 bytes; the most is 32")
    #expect(refusal(start + #""id":"x","label":"\#(String(repeating: "l", count: 17))"}]}"#) == "button label is 17 characters; the most is 16")
    #expect(refusal(start + #""id":"x","label":"Go","symbol":"Not A Symbol"}]}"#)?.contains("button symbol") == true)
}

@Test func priorityIsNormalOrHigh() {
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","priority":"urgent"}"#) == "priority is normal or high")
}

@Test func lastsIsOneSecondToTwelveHours() throws {
    let start = #"{"v":1,"op":"start","id":"a","title":"T","lasts":"#
    #expect(try draft(start + "1}").lasts == 1)
    #expect(try draft(start + "43200}").lasts == 43200)
    #expect(refusal(start + "0}") == "lasts must be a number of seconds from 1 to 43200")
    #expect(refusal(start + "43201}") == "lasts must be a number of seconds from 1 to 43200")
    #expect(refusal(start + #""soon"}"#) == "lasts must be a number of seconds from 1 to 43200")
    #expect(refusal(start + "true}") == "lasts must be a number of seconds from 1 to 43200")
}

@Test func aScriptMustNameItselfAndAnAppsFromIsIgnored() throws {
    #expect(refusal(minimal, isScript: true) == "from is missing; a script names itself with from")
    #expect(try draft(#"{"v":1,"op":"start","id":"a","title":"T","from":"backup"}"#, isScript: true).from == "backup")
    #expect(refusal(#"{"v":1,"op":"start","id":"a","title":"T","from":"\#(String(repeating: "f", count: 31))"}"#, isScript: true) == "from is 31 characters; the most is 30")
    // A signed app's name comes from its signature, so whatever it sends there is never read.
    #expect(try draft(#"{"v":1,"op":"start","id":"a","title":"T","from":"Another app"}"#).from == nil)
}

// MARK: Updates

@Test func anUpdateChangesOnlyTheFieldsItNames() throws {
    let patch = try patch(#"{"v":1,"op":"update","id":"a","detail":"Paused","title":"Paused"}"#)
    #expect(patch == ActivityPatch(title: "Paused", detail: .set("Paused")))
}

@Test func nullClearsTheFieldsThatCanBeCleared() throws {
    let patch = try patch(#"{"v":1,"op":"update","id":"a","detail":null,"badge":null,"icon":null,"clock":null,"buttons":null,"lasts":null}"#)
    #expect(patch == ActivityPatch(detail: .clear, badge: .clear, icon: .clear, clock: .clear, buttons: .clear, lasts: .clear))
}

@Test func theTitleAndPriorityCantBeCleared() {
    #expect(refusal(#"{"v":1,"op":"update","id":"a","title":null}"#) == "title can't be cleared; send a new one instead")
    #expect(refusal(#"{"v":1,"op":"update","id":"a","priority":null}"#) == "priority can't be cleared; send a new one instead")
}

@Test func fromCantChangeOnceTheActivityHasStarted() {
    #expect(refusal(#"{"v":1,"op":"update","id":"a","from":"someone else"}"#) == "from can't change after the activity starts")
    #expect(refusal(#"{"v":1,"op":"update","id":"a","from":null}"#) == "from can't change after the activity starts")
}

@Test func anUpdateIsCheckedAgainstTheLimitsOfAStart() {
    #expect(refusal(#"{"v":1,"op":"update","id":"a","title":"\#(String(repeating: "t", count: 61))"}"#) == "title is 61 characters; the most is 60")
    #expect(refusal(#"{"v":1,"op":"update","id":"a","detail":"\#(String(repeating: "d", count: 101))"}"#) == "detail is 101 characters; the most is 100")
    #expect(refusal(#"{"v":1,"op":"update","id":"a","lasts":99999}"#) == "lasts must be a number of seconds from 1 to 43200")
    #expect(refusal(#"{"v":1,"op":"update","id":"a","buttons":[{"id":"1","label":"a"},{"id":"2","label":"b"},{"id":"3","label":"c"}]}"#) == "buttons has 3; an activity can have 2 at most")
}
