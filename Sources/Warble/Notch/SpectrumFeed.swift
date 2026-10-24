import Foundation
import WarbleModel

/// Something that draws the live waveform.
@MainActor
protocol SpectrumListener: AnyObject {
    /// One frame of bands, as `SpectrumBars` takes them.
    func spectrum(_ bands: [Float])
}

/// Carries the audio tap's frames from the audio queue to the bars that draw them, about 30 a second while the waveform
/// shows and none otherwise. It's the one place a frame crosses to the main actor, and it never passes through `reduce`.
final class SpectrumFeed: @unchecked Sendable {
    /// Read and changed on the main actor only. Weak, so a bar that goes away needs no goodbye.
    nonisolated(unsafe) private let listeners = NSHashTable<AnyObject>.weakObjects()

    /// Called on the audio queue by `EffectRunner.spectrum`.
    func receive(_ bands: [Float]) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                for case let listener as SpectrumListener in listeners.allObjects {
                    listener.spectrum(bands)
                }
            }
        }
    }

    @MainActor
    func add(_ listener: SpectrumListener) {
        listeners.add(listener)
    }

    @MainActor
    func remove(_ listener: SpectrumListener) {
        listeners.remove(listener)
    }
}
