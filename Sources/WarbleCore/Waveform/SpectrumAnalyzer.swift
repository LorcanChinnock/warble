import Accelerate
import Foundation
import WarbleModel

/// Turns a stream of audio samples into the bands of `SpectrumBars`: the biggest tone in each, where a full-scale tone is 1.
/// It keeps the last window of samples and works out a frame every `hop` samples, so the frame rate follows the sample
/// rate rather than the size of the buffers the system hands over. Used from one queue only.
final class SpectrumAnalyzer: @unchecked Sendable {
    /// Samples in each transform. 2048 at 48 kHz puts a bin every 23 Hz, enough for the bass band to hold a few.
    static let size = 2048
    /// Frames a second.
    static let framesPerSecond = 30.0

    private let sampleRate: Double
    private let hop: Int
    private let log2n = vDSP_Length(log2(Double(SpectrumAnalyzer.size)))
    private let setup: FFTSetup
    private let window: [Float]
    private var ring = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var written = 0
    private var sinceFrame = 0
    private var windowed = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var real = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var imaginary = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var magnitudes = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    /// The first and last bin of each band.
    private let ranges: [Range<Int>]

    init?(sampleRate: Double) {
        guard sampleRate > 0, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.sampleRate = sampleRate
        self.setup = setup
        hop = max(Int(sampleRate / Self.framesPerSecond), 1)
        var window = [Float](repeating: 0, count: Self.size)
        vDSP_hann_window(&window, vDSP_Length(Self.size), 0)
        self.window = window
        let binWidth = sampleRate / Double(Self.size)
        let top = Self.size / 2 - 1
        let edges = SpectrumBars.bandEdges.map { min(max(Int(($0 / binWidth).rounded()), 1), top) }
        ranges = (0..<SpectrumBars.count).map { index in edges[index]..<max(edges[index + 1], edges[index] + 1) }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Adds `count` mono samples, and calls `frame` with the bands each time a frame's worth has gone by.
    func push(_ samples: UnsafePointer<Float>, count: Int, frame: ([Float]) -> Void) {
        var offset = 0
        while offset < count {
            // As many as fit before the next frame is due or the ring wraps, copied in one go.
            let at = written % Self.size
            let n = min(count - offset, hop - sinceFrame, Self.size - at)
            ring.withUnsafeMutableBufferPointer { $0.baseAddress!.advanced(by: at).update(from: samples + offset, count: n) }
            written += n
            sinceFrame += n
            offset += n
            if sinceFrame >= hop {
                sinceFrame = 0
                // Not before the ring has filled once.
                if written >= Self.size { frame(bands()) }
            }
        }
    }

    /// The bands of the last window of samples.
    private func bands() -> [Float] {
        // The ring in order, oldest first, under a Hann window: the older part from where the next sample goes to the end,
        // then the newer part from the start.
        let split = written % Self.size
        let older = Self.size - split
        ring.withUnsafeBufferPointer { ring in
            window.withUnsafeBufferPointer { window in
                windowed.withUnsafeMutableBufferPointer { windowed in
                    vDSP_vmul(ring.baseAddress! + split, 1, window.baseAddress!, 1, windowed.baseAddress!, 1, vDSP_Length(older))
                    if split > 0 {
                        vDSP_vmul(ring.baseAddress!, 1, window.baseAddress! + older, 1, windowed.baseAddress! + older, 1, vDSP_Length(split))
                    }
                }
            }
        }
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(Self.size / 2))
            }
        }
        // The transform of a real signal comes out doubled, and a Hann window passes half a tone's amplitude, so a tone of
        // amplitude A peaks at A * size / 2.
        var scale = 2 / Float(Self.size)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(Self.size / 2))
        return ranges.map { range in
            magnitudes[range].max() ?? 0
        }
    }
}
