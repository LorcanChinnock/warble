import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let music = "com.apple.Music"
private let spotify = "com.spotify.client"
private let safari = "com.apple.Safari"

/// Applies each report `seconds` after `start`: `true` playing, `false` paused, `nil` gone.
private func priority(_ reports: (String, Bool?, TimeInterval)..., pinned: String? = nil) -> SourcePriority {
    var priority = SourcePriority(pinned: pinned)
    for (source, isPlaying, seconds) in reports {
        if let isPlaying {
            priority.update(source, isPlaying: isPlaying, at: start + seconds)
        } else {
            priority.remove(source)
        }
    }
    return priority
}

@Test func nothingIsFollowedWithNoSources() {
    #expect(SourcePriority().followed == nil)
}

@Test func theOnlySourceIsFollowedPlayingOrPaused() {
    #expect(priority((music, true, 0)).followed == music)
    #expect(priority((music, true, 0), (music, false, 5)).followed == music)
    #expect(priority((music, false, 0)).followed == music)
}

@Test func theSourceThatStartedMostRecentlyIsFollowed() {
    #expect(priority((music, true, 0), (spotify, true, 5)).followed == spotify)
    #expect(priority((spotify, true, 0), (music, true, 5)).followed == music)
}

@Test func whenTheNewerSourcePausesTheOnePlayingIsFollowed() {
    let paused = priority((music, true, 0), (spotify, true, 5), (spotify, false, 10))
    #expect(paused.followed == music)
    #expect(paused.ranked == [music, spotify])
}

@Test func whenBothPauseTheOneThatPlayedLastIsFollowed() {
    #expect(priority((music, true, 0), (spotify, true, 5), (spotify, false, 10), (music, false, 20)).followed == music)
    #expect(priority((music, true, 0), (spotify, true, 5), (music, false, 10), (spotify, false, 20)).followed == spotify)
}

@Test func resumingAnOlderSourceMakesItTheNewest() {
    let resumed = priority((music, true, 0), (music, false, 2), (spotify, true, 5), (music, true, 10))
    #expect(resumed.followed == music)
    #expect(resumed.ranked == [music, spotify])
}

@Test func whenTheFollowedSourceStopsTheOtherIsFollowed() {
    #expect(priority((music, true, 0), (spotify, true, 5), (spotify, nil, 10)).followed == music)
    #expect(priority((music, true, 0), (spotify, false, 5), (music, nil, 10)).followed == spotify)
    #expect(priority((music, true, 0), (music, nil, 5)).followed == nil)
}

@Test func aSourceThatStopsAndComesBackStartsAfresh() {
    let back = priority((music, true, 0), (spotify, true, 5), (music, nil, 10), (music, false, 20))
    // Paused when it came back, so the one still playing comes first.
    #expect(back.ranked == [spotify, music])
}

@Test func aReportThatChangesNothingKeepsTheOrder() {
    // Sources report again whenever anything changes, such as the position, not only when they start.
    #expect(priority((music, true, 0), (spotify, true, 5), (music, true, 10)).followed == spotify)
}

@Test func aPinnedSourceWinsWhileItsThere() {
    #expect(priority((music, true, 0), (spotify, true, 5), pinned: music).followed == music)
    #expect(priority((music, false, 0), (spotify, true, 5), pinned: music).followed == music)
    #expect(priority((music, true, 0), (spotify, true, 5), (music, nil, 6), pinned: music).followed == spotify)
}

@Test func aPinnedSourceThatComesBackIsFollowedAgain() {
    #expect(priority((spotify, true, 0), (music, true, 5), (music, nil, 6), (music, false, 10), pinned: music).followed == music)
}

@Test func videoCallsAreIgnoredByDefault() {
    let call = priority((music, true, 0), (spotify, false, 1), ("us.zoom.xos", true, 5), ("com.apple.FaceTime", true, 6), ("com.microsoft.teams2", true, 7))
    #expect(call.followed == music)
    #expect(call.ranked == [music, spotify])
}

@Test func anIgnoredSourceIsNeverFollowedEvenAlone() {
    #expect(priority(("us.zoom.xos", true, 0)).followed == nil)
}

@Test func anIgnoredSourceIsNeverFollowedEvenPinned() {
    var priority = priority((music, true, 0), (safari, true, 5), pinned: safari)
    priority.ignored.insert(safari)
    #expect(priority.followed == music)
}

@Test func takingAnAppOffTheIgnoreListShowsItAgain() {
    var priority = priority((music, true, 0), ("us.zoom.xos", true, 5))
    priority.ignored.remove("us.zoom.xos")
    #expect(priority.followed == "us.zoom.xos")
}

@Test func sourcesThatStartedTogetherHaveAStableOrder() {
    #expect(priority((spotify, true, 0), (music, true, 0)).ranked == [music, spotify])
    #expect(priority((music, true, 0), (spotify, true, 0)).ranked == [music, spotify])
}
