import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WarbleCore
import WarbleModel

/// Times the pure paths that have budgets in `docs/performance.md`: what happens between the player reporting a change and
/// the notch showing it. `make test` skips this suite and `make perf` runs it alone, one test at a time, so other tests
/// don't skew the timings. Budgets are 2× the baseline measured on the CI runner, the slowest machine that runs them,
/// which leaves room for noise but still fails on a regression that does the work again on every call.
@Suite(.serialized) struct PerfTests {
    /// A new track arrives as one line holding everything, its art included, which `AdapterSource` reads before the notch
    /// hears of it.
    @Test func readingANewTrackWithItsArtStaysInBudget() throws {
        let line = try trackLine(art: cover())
        let time = try fastest {
            var stream = AdapterStream()
            let changed = try stream.apply(line, at: .now)
            #expect(changed)
        }
        try check(time, budget: .microseconds(Budget.trackLine), "New track with art")
    }

    /// A pause, a play or a seek comes as a short line that changes one or two keys of what's already known, art and all.
    @Test func readingAPauseStaysInBudget() throws {
        var stream = AdapterStream()
        try stream.apply(try trackLine(art: cover()), at: .now)
        var playing = true
        let time = try fastest {
            playing.toggle()
            let changed = try stream.apply(Data(#"{"type":"data","diff":true,"payload":{"playing":\#(playing)}}"#.utf8), at: .now)
            #expect(changed)
        }
        try check(time, budget: .microseconds(Budget.pauseLine), "Pause")
    }

    /// The expanded card's glow takes its colours from each new track's art, off the main thread.
    @Test func pickingTheArtsColoursStaysInBudget() throws {
        let art = try cover()
        let time = try fastest {
            #expect(ArtworkColours(data: art) != nil)
        }
        try check(time, budget: .microseconds(Budget.artworkColours), "Artwork colours")
    }
}

/// Twice the CI runner's baselines in `docs/performance.md`, in microseconds; change both together.
private enum Budget {
    static let trackLine = 1012.0
    static let pauseLine = 16.2
    static let artworkColours = 2809.0
}

/// The fastest run of `body`, after one untimed run that warms caches. It runs at least fifteen times and for at least
/// half a second. A busy runner can only add time, so the fastest run is the closest to what the work costs, and a
/// slow spell would have to last the whole half second to fail the test.
private func fastest(_ body: () throws -> Void) throws -> Duration {
    try body()
    let clock = ContinuousClock()
    let start = clock.now
    var best = Duration.seconds(Int64.max)
    var runs = 0
    while runs < 15 || clock.now - start < .milliseconds(500) {
        best = min(best, try clock.measure(body))
        runs += 1
    }
    return best
}

private func check(_ time: Duration, budget: Duration, _ name: String) throws {
    let style = Duration.UnitsFormatStyle(allowedUnits: [.milliseconds, .microseconds], width: .abbreviated, fractionalPart: .show(length: 2))
    print("\(name): \(time.formatted(style)), budget \(budget.formatted(style))")
    #expect(time <= budget, "\(name) took \(time), over its \(budget) budget")
}

/// A 600×600 album cover as a JPEG, the size Music and Spotify usually report: two gradients and a scatter of discs, so
/// it compresses about as much as a real cover rather than to nothing.
private func cover() throws -> Data {
    let side = 600
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let colours = [CGColor(srgbRed: 0.8, green: 0.2, blue: 0.3, alpha: 1), CGColor(srgbRed: 0.1, green: 0.2, blue: 0.6, alpha: 1)] as CFArray
    let gradient = try #require(CGGradient(colorsSpace: space, colors: colours, locations: nil))
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
    var seed: UInt64 = 42
    func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(1 << 31)
    }
    for _ in 0..<200 {
        context.setFillColor(CGColor(srgbRed: next(), green: next(), blue: next(), alpha: 0.6))
        let size = 10 + next() * 60
        context.fillEllipse(in: CGRect(x: next() * Double(side), y: next() * Double(side), width: size, height: size))
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// The line the adapter sends when a new track starts in Music, as in the recorded fixtures, with `art` as its artwork.
private func trackLine(art: Data) throws -> Data {
    let payload: [String: Any] = [
        "bundleIdentifier": "com.apple.Music",
        "title": "A track with a title long enough to scroll",
        "artist": "An artist",
        "album": "An album",
        "playing": true,
        "playbackRate": 1,
        "durationMicros": 240_000_000,
        "elapsedTimeMicros": 0,
        "timestampEpochMicros": Date.now.timeIntervalSince1970 * 1_000_000,
        "artworkMimeType": "image/jpeg",
        "artworkData": art.base64EncodedString(),
    ]
    return try JSONSerialization.data(withJSONObject: ["type": "data", "diff": false, "payload": payload])
}
