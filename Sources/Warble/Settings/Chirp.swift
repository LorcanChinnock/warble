import AVFoundation

/// A bird's two-note chirp, made of sine sweeps when first asked for, so it ships no audio file. One at a time: asking
/// while it is still sounding does nothing.
@MainActor
enum Chirp {
    private static var player: AVAudioPlayer?

    static func play() {
        if player?.isPlaying == true { return }
        player = player ?? (try? AVAudioPlayer(data: wave))
        player?.volume = 0.5
        player?.currentTime = 0
        player?.play()
    }

    private static let sampleRate = 22_050.0

    /// 16-bit mono WAV: two chirps, each a quick rise in pitch with a flutter, and a short gap between them.
    private static let wave: Data = {
        let notes: [(start: Double, end: Double)] = [(3_000, 4_800), (3_400, 5_200)]
        var samples: [Int16] = []
        for (index, note) in notes.enumerated() {
            let count = Int(0.12 * sampleRate)
            var phase = 0.0
            for step in 0..<count {
                let progress = Double(step) / Double(count)
                let flutter = 1 + 0.04 * sin(2 * .pi * 40 * Double(step) / sampleRate)
                phase += 2 * .pi * (note.start + (note.end - note.start) * progress) * flutter / sampleRate
                let envelope = pow(sin(.pi * progress), 2)
                samples.append(Int16(sin(phase) * envelope * 0.6 * Double(Int16.max)))
            }
            if index < notes.count - 1 {
                samples += [Int16](repeating: 0, count: Int(0.08 * sampleRate))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes); data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2)
        append(UInt16(2)); append(UInt16(16)); data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in samples { append(sample) }
        return data
    }()
}
