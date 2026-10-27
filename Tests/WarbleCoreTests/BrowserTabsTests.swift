import Testing
@testable import WarbleCore

@Test func safariTabsAreSelectedWithCurrentTab() throws {
    let script = try #require(BrowserTabs.script(bundleIdentifier: "com.apple.Safari", title: "Song"))
    #expect(script.contains("contains \"Song\""))
    #expect(script.contains("name of t as text"))
    #expect(script.contains("set current tab of w to t"))
}

@Test func chromiumTabsAreSelectedByIndex() throws {
    let script = try #require(BrowserTabs.script(bundleIdentifier: "com.google.Chrome", title: "Song"))
    #expect(script.contains("title of t as text"))
    #expect(script.contains("set active tab index of w to i"))
}

@Test func aTitleWithQuotesAndBackslashesCannotEndTheScriptString() throws {
    let script = try #require(BrowserTabs.script(bundleIdentifier: "com.apple.Safari", title: #"A "B" \ C"#))
    #expect(script.contains(#"contains "A \"B\" \\ C""#))
}

@Test func appsThatAreNotBrowsersHaveNoTabScript() {
    #expect(BrowserTabs.script(bundleIdentifier: "com.apple.Music", title: "Song") == nil)
}
