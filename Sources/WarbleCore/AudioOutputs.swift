import CoreAudio
import Foundation
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "outputs")

/// The Mac's sound outputs and which one plays, through Core Audio. Choosing one sets the default output, as the Sound
/// settings do, which needs no permission. AirPlay receivers aren't Core Audio devices, so they never appear here.
@MainActor
public final class AudioOutputs {
    private var onChange: (() -> Void)?
    private var listeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    public init() {}

    /// The outputs to offer, in `AudioOutput.choices` order.
    public var all: [AudioOutput] {
        AudioOutput.choices(deviceIDs().map(output))
    }

    /// The default output's ID.
    public var current: UInt32 {
        var output = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultOutputAddress
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &output)
        return output
    }

    /// Makes `id` the default output. `SystemVolume` follows it.
    public func select(_ id: UInt32) {
        var device = AudioObjectID(id)
        var address = Self.defaultOutputAddress
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &device)
        if status != noErr {
            log.error("Couldn't make device \(id) the output: \(status)")
        }
    }

    /// Calls `onChange` whenever a device comes or goes, or the default output changes, until `stopListening()`. Listen
    /// only while the outputs show.
    public func startListening(_ onChange: @escaping () -> Void) {
        stopListening()
        self.onChange = onChange
        for address in [Self.devicesAddress, Self.defaultOutputAddress] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            var address = address
            guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr else { continue }
            listeners.append((address, block))
        }
    }

    public func stopListening() {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener.block)
        }
        listeners = []
        onChange = nil
    }

    private func deviceIDs() -> [AudioObjectID] {
        var address = Self.devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func output(_ id: AudioObjectID) -> AudioOutput {
        AudioOutput(
            id: id,
            name: name(of: id),
            transport: AudioOutput.Transport(code: uint32(id, kAudioDevicePropertyTransportType) ?? 0),
            // `hdpn`, the headphone jack's data source.
            isHeadphoneJack: uint32(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput) == 0x6864_706E,
            hasOutputChannels: outputChannels(of: id) > 0,
            canBeDefault: (uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput) ?? 0) != 0,
            isHidden: (uint32(id, kAudioDevicePropertyIsHidden) ?? 0) != 0
        )
    }

    private func name(of id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "" }
        return name.takeRetainedValue() as String
    }

    private func outputChannels(of id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}
