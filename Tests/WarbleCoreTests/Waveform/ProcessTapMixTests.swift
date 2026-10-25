import AudioToolbox
import Foundation
import Testing
@testable import WarbleCore

/// Runs `mix` over buffers made from `channels`, each an array of samples, laid out one buffer a channel or all in one.
private func mixed(_ channels: [[Float]], interleaved: Bool, capacity: Int = 16) -> [Float] {
    let frames = channels[0].count
    let data = interleaved ? [(0..<frames).flatMap { frame in channels.map { $0[frame] } }] : channels
    let list = AudioBufferList.allocate(maximumBuffers: data.count)
    defer { free(list.unsafeMutablePointer) }
    var pointers: [UnsafeMutablePointer<Float>] = []
    for index in data.indices {
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: data[index].count)
        pointer.initialize(from: data[index], count: data[index].count)
        pointers.append(pointer)
        list[index] = AudioBuffer(
            mNumberChannels: interleaved ? UInt32(channels.count) : 1,
            mDataByteSize: UInt32(data[index].count * MemoryLayout<Float>.size), mData: pointer
        )
    }
    defer { pointers.forEach { $0.deallocate() } }
    var mono = [Float](repeating: -1, count: capacity)
    ProcessTap.mix(list, channels: channels.count, interleaved: interleaved, into: &mono)
    return Array(mono.prefix(frames))
}

@Test func interleavedChannelsAreAveraged() {
    let result = mixed([[1, 0.5, -1, 0], [0, 0.5, 1, 0.5]], interleaved: true)
    #expect(result == [0.5, 0.5, 0, 0.25])
}

@Test func separateChannelsAreAveraged() {
    let result = mixed([[1, 0.5, -1, 0], [0, 0.5, 1, 0.5]], interleaved: false)
    #expect(result == [0.5, 0.5, 0, 0.25])
}

@Test func oneChannelPassesThrough() {
    #expect(mixed([[0.25, -0.5, 1]], interleaved: true) == [0.25, -0.5, 1])
    #expect(mixed([[0.25, -0.5, 1]], interleaved: false) == [0.25, -0.5, 1])
}

@Test func moreFramesThanTheBufferHoldsAreCutOff() {
    let result = mixed([[Float](repeating: 1, count: 8), [Float](repeating: 1, count: 8)], interleaved: true, capacity: 4)
    #expect(result.count == 4)
}
