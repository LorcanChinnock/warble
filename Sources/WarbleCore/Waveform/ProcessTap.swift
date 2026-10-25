import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import os
import WarbleModel

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "waveform")

/// Listens to the Mac's audio with a Core Audio process tap (macOS 14.2+), read through an aggregate device, and turns it
/// into `SpectrumBars`' bands. It holds the tap, the aggregate device and the IOProc only between `start` and `stop`, and
/// starting is what makes macOS ask to record.
@MainActor
public final class ProcessTap: AudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "dev.lorcan.Warble.waveform", qos: .userInteractive)
    private var callbacks: (onFrame: @Sendable ([Float]) -> Void, onFailure: @Sendable () -> Void)?
    /// Follows the default output, since the aggregate device is clocked by the output it started with.
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var outputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
    )

    public init() {}

    public func start(onFrame: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable () -> Void) {
        stop()
        callbacks = (onFrame, onFailure)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.restart() }
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, .main, listener)
        begin()
    }

    public func stop() {
        if let outputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, .main, outputListener)
        }
        outputListener = nil
        callbacks = nil
        release()
    }

    /// Moves to the new default output, with the same callbacks.
    private func restart() {
        guard callbacks != nil else { return }
        release()
        begin()
    }

    private func begin() {
        guard let callbacks else { return }
        do {
            try build(onFrame: callbacks.onFrame)
        } catch {
            log.error("The audio tap didn't start: \(String(describing: error), privacy: .public)")
            release()
            callbacks.onFailure()
        }
    }

    private struct TapError: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) failed with \(status)" }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw TapError(step: step, status: status) }
    }

    private func build(onFrame: @escaping @Sendable ([Float]) -> Void) throws {
        let output = try defaultOutputUID()
        // Everything the Mac plays, mixed to stereo and left audible; private, so no other app sees the device.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "creating the tap")

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Warble waveform",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "creating the aggregate device")

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "reading the tap's format")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32,
              let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)
        else { throw TapError(step: "reading a format Warble can use", status: -1) }
        let channels = max(Int(format.mChannelsPerFrame), 1)
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        let block = Self.ioBlock(channels: channels, interleaved: interleaved, analyzer: analyzer, onFrame: onFrame)
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, block), "creating the IOProc")
        try check(AudioDeviceStart(aggregateID, procID), "starting the device")
    }

    /// What the system calls on the audio queue for each buffer. Made here, outside the main actor, since the closure
    /// would otherwise take the main actor's isolation and trap on the audio queue.
    private nonisolated static func ioBlock(
        channels: Int, interleaved: Bool, analyzer: SpectrumAnalyzer, onFrame: @escaping @Sendable ([Float]) -> Void
    ) -> AudioDeviceIOBlock {
        let mono = MonoBuffer()
        return { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let frames = Self.frames(in: buffers, channels: channels, interleaved: interleaved) else { return }
            Self.mix(buffers, channels: channels, interleaved: interleaved, into: &mono.samples)
            mono.samples.withUnsafeBufferPointer { analyzer.push($0.baseAddress!, count: min(frames, $0.count), frame: onFrame) }
        }
    }

    private final class MonoBuffer: @unchecked Sendable {
        var samples = [Float](repeating: 0, count: 4096)
    }

    /// How many frames of samples the buffers hold.
    private nonisolated static func frames(in buffers: UnsafeMutableAudioBufferListPointer, channels: Int, interleaved: Bool) -> Int? {
        guard let first = buffers.first else { return nil }
        let samples = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        return interleaved ? samples / channels : samples
    }

    /// The channels averaged into one.
    nonisolated static func mix(
        _ buffers: UnsafeMutableAudioBufferListPointer, channels: Int, interleaved: Bool, into mono: inout [Float]
    ) {
        guard let frames = frames(in: buffers, channels: channels, interleaved: interleaved) else { return }
        let count = vDSP_Length(min(frames, mono.count))
        var average = 1 / Float(channels)
        mono.withUnsafeMutableBufferPointer { mono in
            guard let out = mono.baseAddress else { return }
            if interleaved {
                guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                let stride = vDSP_Stride(channels)
                vDSP_vsmul(data, stride, &average, out, 1, count)
                for channel in 1..<max(channels, 1) { vDSP_vsma(data + channel, stride, &average, out, 1, out, 1, count) }
            } else {
                var first = true
                for channel in 0..<min(channels, buffers.count) {
                    guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    if first {
                        vDSP_vsmul(data, 1, &average, out, 1, count)
                        first = false
                    } else {
                        vDSP_vsma(data, 1, &average, out, 1, out, 1, count)
                    }
                }
                if first { vDSP_vclr(out, 1, count) }
            }
        }
    }

    private func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddress, 0, nil, &size, &device), "finding the output")
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, &uid), "reading the output's ID")
        guard let uid else { throw TapError(step: "reading the output's ID", status: -1) }
        return uid.takeRetainedValue() as String
    }

    /// Stops and destroys whatever is held, in the reverse order it was made.
    private func release() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
