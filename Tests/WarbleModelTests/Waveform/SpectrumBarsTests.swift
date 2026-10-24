import Testing
@testable import WarbleModel

@Test func silenceLeavesEveryBarAtRest() {
    var bars = SpectrumBars()
    #expect(bars.update([0, 0, 0, 0]) == [0, 0, 0, 0])
    #expect(bars.update([Float.nan, -1, .infinity, 1e-9]) == [0, 0, 0, 0])
}

@Test func aSingleToneRaisesOnlyItsBar() {
    var bars = SpectrumBars()
    var heights: [Double] = []
    for _ in 0..<10 {
        heights = bars.update([0, 0, 0.1, 0])
    }
    #expect(heights[2] > 0.5)
    #expect(heights[0] == 0 && heights[1] == 0 && heights[3] == 0)
    #expect(heights.max() == heights[2])
}

@Test func aLouderBandMakesATallerBar() {
    var quiet = SpectrumBars()
    var loud = SpectrumBars()
    for _ in 0..<20 {
        quiet.update([0.001, 0, 0, 0])
        loud.update([0.1, 0, 0, 0])
    }
    #expect(loud.heights[0] > quiet.heights[0])
    #expect(loud.heights.allSatisfy { $0 <= 1 })
}

@Test func barsRiseFasterThanTheyFall() {
    var bars = SpectrumBars()
    let risen = bars.update([0.3, 0.3, 0.3, 0.3])[0]
    #expect(risen > 0.5)
    let fallen = bars.update([0, 0, 0, 0])[0]
    #expect(fallen > risen * 0.5)
    #expect(fallen < risen)
}

@Test func theBarsSettleBackWhenTheSoundStops() {
    var bars = SpectrumBars()
    bars.update([0.3, 0.3, 0.3, 0.3])
    for _ in 0..<60 {
        bars.update([0, 0, 0, 0])
    }
    #expect(bars.heights.allSatisfy { $0 < 0.001 })
    bars.update([0.3, 0.3, 0.3, 0.3])
    bars.reset()
    #expect(bars.heights == [0, 0, 0, 0])
}

@Test func aFrameOfTheWrongSizeIsSilence() {
    var bars = SpectrumBars()
    #expect(bars.update([0.5]) == [0, 0, 0, 0])
}

@Test func theBandsCoverBassToTrebleAndMatchTheFourBars() {
    #expect(SpectrumBars.count == 4)
    #expect(SpectrumBars.bandEdges == SpectrumBars.bandEdges.sorted())
}
