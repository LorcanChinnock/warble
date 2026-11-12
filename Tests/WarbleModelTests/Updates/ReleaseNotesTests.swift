import Foundation
import Testing
@testable import WarbleModel

/// Three releases as the release workflow embeds them: each GitHub release's body, newest first.
private let embedded = """
## [0.2.0](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.23...v0.2.0) (2026-11-20)


### Features

* **settings:** a native Settings window with Notch, General and About tabs ([#438](https://github.com/LorcanChinnock/warble/issues/438)) ([13a3dff](https://github.com/LorcanChinnock/warble/commit/13a3dff))
* **update:** Warble's own update window ([#430](https://github.com/LorcanChinnock/warble/issues/430)) ([abc1234](https://github.com/LorcanChinnock/warble/commit/abc1234def))


### Bug Fixes

* keep `Check for Updates…` working ([#1](https://example.com/1))

## [0.1.0-beta.23](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.22...v0.1.0-beta.23) (2026-11-06)


### Performance Improvements

* **notch:** open the notch sooner ([#400](https://github.com/LorcanChinnock/warble/issues/400)) ([d8d6a10](https://github.com/LorcanChinnock/warble/commit/d8d6a10))

### Miscellaneous Chores

* **deps:** bump Sparkle ([#401](https://github.com/LorcanChinnock/warble/issues/401)) ([cad7f4a](https://github.com/LorcanChinnock/warble/commit/cad7f4a))

## [0.1.0-beta.22](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.21...v0.1.0-beta.22) (2026-11-02)


### Bug Fixes

* **player:** a song from Spotify shows its art again ([#390](https://github.com/LorcanChinnock/warble/issues/390)) ([36de933](https://github.com/LorcanChinnock/warble/commit/36de933))
"""

@Test func releaseNotesReadEachVersionAndItsGroups() {
    let notes = ReleaseNotes(embedded, format: .markdown)
    #expect(notes.versions.map(\.version) == ["0.2.0", "0.1.0-beta.23", "0.1.0-beta.22"])
    #expect(notes.versions[0].groups == [
        ReleaseNotes.Group(kind: .new, items: [
            "A native Settings window with Notch, General and About tabs",
            "Warble's own update window",
        ]),
        ReleaseNotes.Group(kind: .fixed, items: ["Keep Check for Updates… working"]),
    ])
    #expect(notes.versions[1].groups.map(\.kind) == [.faster, .other("Miscellaneous Chores")])
    #expect(notes.versions[1].groups[1].items == ["Bump Sparkle"])
}

@Test func releaseNotesKeepOnlyVersionsNewerThanTheInstalledOne() {
    let notes = ReleaseNotes(embedded, format: .markdown)
    #expect(notes.since("0.1.0-beta.23").versions.map(\.version) == ["0.2.0"])
    #expect(notes.since("v0.1.0-beta.22").versions.map(\.version) == ["0.2.0", "0.1.0-beta.23"])
}

@Test func releaseNotesKeepEveryVersionWhenTheInstalledOneIsOlderThanAll() {
    let notes = ReleaseNotes(embedded, format: .markdown)
    #expect(notes.since("0.1.0-beta.3").versions.count == 3)
}

@Test func releaseNotesWithoutHeadingsAreOneUntitledGroup() {
    let notes = ReleaseNotes("Some words first.\n- one\n-\n• two", format: .plainText)
    #expect(notes.versions == [ReleaseNotes.Version(version: nil, groups: [ReleaseNotes.Group(kind: .untitled, items: ["One", "Two"])])])
}

@Test func releaseNotesNeedAList() {
    #expect(ReleaseNotes("Just a paragraph about the release.", format: .plainText).isEmpty)
    #expect(ReleaseNotes("## 0.2.0\n\n### Features\n", format: .markdown).isEmpty)
    #expect(ReleaseNotes("", format: .markdown).versions.isEmpty)
}

@Test func releaseNotesReadHTMLLists() {
    let notes = ReleaseNotes("<h2>New</h2><ul><li>Hides <b>emails</b> &amp; names</li>\n<li class=\"x\">Shows &amp;lt;tags&amp;gt;</li></ul><p>Thanks!</p>", format: .html)
    #expect(notes.versions.first?.groups.first?.items == ["Hides emails & names", "Shows &lt;tags&gt;"])
}

@Test func releaseNotesFormatFromSparkleAndFromAFile() {
    #expect(ReleaseNotes.format(sparkle: "markdown") == .markdown)
    #expect(ReleaseNotes.format(sparkle: "plain-text") == .plainText)
    #expect(ReleaseNotes.format(sparkle: nil) == .html)
    #expect(ReleaseNotes.format(mimeType: "text/markdown", pathExtension: nil) == .markdown)
    #expect(ReleaseNotes.format(mimeType: nil, pathExtension: "md") == .markdown)
    #expect(ReleaseNotes.format(mimeType: "text/plain", pathExtension: "html") == .plainText)
    #expect(ReleaseNotes.format(mimeType: "text/html", pathExtension: "html") == .html)
}
