import AudioToolbox
import CoreAudio
import Foundation

/// The volume of the Mac's default output, as the volume keys and Control Centre's slider set it, through Core Audio.
/// It follows the output when it changes, such as when AirPods connect.
@MainActor
public final class SystemVolume {
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var onChange: (() -> Void)?
    /// The listeners added, each with what removes it.
    private var listeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    public init() {}

    /// From 0 to 1, or `nil` when the output has no volume Warble can change, such as some digital outputs.
    public var volume: Double? {
        let output = defaultOutput()
        guard isSettable(output, Self.volumeAddress) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.volumeAddress
        guard AudioObjectGetPropertyData(output, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    public var isMuted: Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.muteAddress
        return AudioObjectGetPropertyData(defaultOutput(), &address, 0, nil, &size, &value) == noErr && value != 0
    }

    /// Sets the volume, and unmutes above silence as the volume keys do.
    public func set(_ volume: Double) {
        let output = defaultOutput()
        var value = Float32(min(max(volume, 0), 1))
        var address = Self.volumeAddress
        AudioObjectSetPropertyData(output, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if volume > 0, isMuted, isSettable(output, Self.muteAddress) {
            var unmuted: UInt32 = 0
            var address = Self.muteAddress
            AudioObjectSetPropertyData(output, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuted)
        }
    }

    /// Calls `onChange` whenever the volume, mute or output changes, from anywhere, until `stopListening()`. Listen only
    /// while the volume shows, so Warble does nothing for volume changes nobody sees.
    public func startListening(_ onChange: @escaping () -> Void) {
        stopListening()
        self.onChange = onChange
        listen(to: AudioObjectID(kAudioObjectSystemObject), Self.defaultOutputAddress) { [weak self] in
            self?.listenToDevice()
            self?.onChange?()
        }
        listenToDevice()
    }

    public func stopListening() {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
        }
        listeners = []
        device = AudioObjectID(kAudioObjectUnknown)
        onChange = nil
    }

    /// Moves the volume and mute listeners to the current output.
    private func listenToDevice() {
        listeners.removeAll { listener in
            guard listener.object == device else { return false }
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
            return true
        }
        device = defaultOutput()
        for address in [Self.volumeAddress, Self.muteAddress] {
            listen(to: device, address) { [weak self] in self?.onChange?() }
        }
    }

    private func listen(to object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ handler: @escaping @MainActor () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        var address = address
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return }
        listeners.append((object, address, block))
    }

    private func defaultOutput() -> AudioObjectID {
        var output = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultOutputAddress
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &output)
        return output
    }

    private func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    /// The device's overall volume across its channels, as the volume keys set it.
    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
}
