import Testing
@testable import WarbleModel

private let cut = TrackTitle.Line.faded("A very long title")

@Test func aTitleThatDoesntFitScrollsWhilePlaying() {
    #expect(TitleScroll.scrolls(cut, isPlaying: true, reduceMotion: false))
}

@Test func aTitleStaysStillWhenPausedOrWithReduceMotion() {
    #expect(!TitleScroll.scrolls(cut, isPlaying: false, reduceMotion: false))
    #expect(!TitleScroll.scrolls(cut, isPlaying: true, reduceMotion: true))
}

@Test func aTitleThatFitsNeverScrolls() {
    #expect(!TitleScroll.scrolls(.title("Short"), isPlaying: true, reduceMotion: false))
    #expect(!TitleScroll.scrolls(.titleAndArtist(title: "Short", artist: "Band"), isPlaying: true, reduceMotion: false))
}

@Test func aLoopMovesTheTitleItsOwnWidthAndTheGapAtAboutEighteenPointsASecond() {
    #expect(TitleScroll.distance(textWidth: 200) == 200 + TitleScroll.gap)
    #expect(TitleScroll.duration(textWidth: 144) == (144 + TitleScroll.gap) / 18)
}

@Test func aLineWiderThanItsRoomScrollsWhilePlaying() {
    #expect(TitleScroll.scrolls(textWidth: 300, width: 200, isPlaying: true, reduceMotion: false))
    #expect(!TitleScroll.scrolls(textWidth: 200, width: 200, isPlaying: true, reduceMotion: false))
    #expect(!TitleScroll.scrolls(textWidth: 300, width: 200, isPlaying: false, reduceMotion: false))
    #expect(!TitleScroll.scrolls(textWidth: 300, width: 200, isPlaying: true, reduceMotion: true))
}
