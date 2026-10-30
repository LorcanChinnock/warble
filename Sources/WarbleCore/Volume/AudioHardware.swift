import AudioToolbox
import CoreAudio

/// What `SystemVolume` reads and sets on an audio object, named apart from Core Audio's addresses.
enum AudioProperty {
    case defaultOutput, volume, mute

    var address: AudioObjectPropertyAddress {
        switch self {
        case .defaultOutput:
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        case .volume:
            // The device's overall volume across its channels, as the volume keys set it.
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
        case .mute:
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
        }
    }
}

/// The Core Audio calls `SystemVolume` makes, so a test can stand in for a Mac's sound hardware.
@MainActor
protocol AudioHardware {
    func defaultOutput() -> AudioObjectID
    /// Whether `object` has the property and it can be set.
    func isSettable(_ object: AudioObjectID, _ property: AudioProperty) -> Bool
    func float(_ object: AudioObjectID, _ property: AudioProperty) -> Float32?
    func uint32(_ object: AudioObjectID, _ property: AudioProperty) -> UInt32?
    func set(_ object: AudioObjectID, _ property: AudioProperty, float: Float32)
    func set(_ object: AudioObjectID, _ property: AudioProperty, uint32: UInt32)
    /// Calls `handler` on the main queue whenever the property changes. Returns what removes the listener, or `nil`
    /// when it couldn't be added.
    func listen(to object: AudioObjectID, _ property: AudioProperty, _ handler: @escaping @MainActor () -> Void) -> (() -> Void)?
}

/// Core Audio itself.
@MainActor
struct CoreAudioHardware: AudioHardware {
    func defaultOutput() -> AudioObjectID {
        uint32(AudioObjectID(kAudioObjectSystemObject), .defaultOutput) ?? AudioObjectID(kAudioObjectUnknown)
    }

    func isSettable(_ object: AudioObjectID, _ property: AudioProperty) -> Bool {
        var address = property.address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    func float(_ object: AudioObjectID, _ property: AudioProperty) -> Float32? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = property.address
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    func uint32(_ object: AudioObjectID, _ property: AudioProperty) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = property.address
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    func set(_ object: AudioObjectID, _ property: AudioProperty, float: Float32) {
        var value = float
        var address = property.address
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    func set(_ object: AudioObjectID, _ property: AudioProperty, uint32: UInt32) {
        var value = uint32
        var address = property.address
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func listen(to object: AudioObjectID, _ property: AudioProperty, _ handler: @escaping @MainActor () -> Void) -> (() -> Void)? {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        var address = property.address
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        return {
            var address = property.address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
    }
}
