import Foundation
import Testing
import WarbleModel
@testable import WarbleCore

private func tone(_ frequency: Double, amplitude: Float, seconds: Double = 1, sampleRate: Double = 48_000) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
}

private func frames(of samples: [Float], sampleRate: Double = 48_000) throws -> [[Float]] {
    let analyzer = try #require(SpectrumAnalyzer(sampleRate: sampleRate))
    var frames: [[Float]] = []
    // In buffers of the size the system hands over, so frames don't depend on how the samples arrive.
    for start in stride(from: 0, to: samples.count, by: 512) {
        let chunk = Array(samples[start..<min(start + 512, samples.count)])
        chunk.withUnsafeBufferPointer { analyzer.push($0.baseAddress!, count: $0.count) { frames.append($0) } }
    }
    return frames
}

@Test func aToneShowsInItsBandAtItsAmplitude() throws {
    let last = try #require(try frames(of: tone(2000, amplitude: 0.5)).last)
    #expect(last.count == SpectrumBars.count)
    // 2 kHz is the third band, and a Hann window loses at most 1.5 dB between bins.
    #expect(last[2] > 0.4 && last[2] < 0.55)
    #expect(last[0] < 0.01 && last[3] < 0.05)
}

@Test func eachToneLandsInItsOwnBand() throws {
    for (frequency, band) in [(100.0, 0), (500.0, 1), (2000.0, 2), (8000.0, 3)] {
        let last = try #require(try frames(of: tone(frequency, amplitude: 0.3)).last)
        #expect(last.firstIndex(of: last.max()!) == band)
    }
}

@Test func silenceGivesEmptyBands() throws {
    let last = try #require(try frames(of: [Float](repeating: 0, count: 48_000)).last)
    #expect(last == [0, 0, 0, 0])
}

@Test func framesComeAboutThirtyTimesASecond() throws {
    let count = try frames(of: tone(440, amplitude: 0.5)).count
    // A second of audio, less the first window, which is filled before the first frame.
    #expect((26...30).contains(count))
}

@Test func aSampleRateOfNothingIsRefused() {
    #expect(SpectrumAnalyzer(sampleRate: 0) == nil)
}
