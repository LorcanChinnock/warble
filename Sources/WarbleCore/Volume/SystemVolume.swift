import CoreAudio
import Foundation

/// The volume of the Mac's default output, as the volume keys and Control Centre's slider set it, through Core Audio.
/// It follows the output when it changes, such as when AirPods connect.
@MainActor
public final class SystemVolume: VolumeControl {
    private let hardware: any AudioHardware
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var onChange: (() -> Void)?
    /// The listeners added, each with the object it listens to and what removes it.
    private var listeners: [(object: AudioObjectID, remove: () -> Void)] = []

    public convenience init() {
        self.init(hardware: CoreAudioHardware())
    }

    init(hardware: any AudioHardware) {
        self.hardware = hardware
    }

    /// From 0 to 1, or `nil` when the output has no volume Warble can change, such as some digital outputs.
    public var volume: Double? {
        let output = hardware.defaultOutput()
        guard hardware.isSettable(output, .volume) else { return nil }
        return hardware.float(output, .volume).map(Double.init)
    }

    public var isMuted: Bool {
        hardware.uint32(hardware.defaultOutput(), .mute).map { $0 != 0 } ?? false
    }

    /// Sets the volume, and unmutes above silence as the volume keys do.
    public func set(_ volume: Double) {
        let output = hardware.defaultOutput()
        hardware.set(output, .volume, float: Float32(min(max(volume, 0), 1)))
        if volume > 0, isMuted, hardware.isSettable(output, .mute) {
            hardware.set(output, .mute, uint32: 0)
        }
    }

    /// Calls `onChange` whenever the volume, mute or output changes, from anywhere, until `stopListening()`. Listen only
    /// while the volume shows, so Warble does nothing for volume changes nobody sees.
    public func startListening(_ onChange: @escaping () -> Void) {
        stopListening()
        self.onChange = onChange
        listen(to: AudioObjectID(kAudioObjectSystemObject), .defaultOutput) { [weak self] in
            self?.listenToDevice()
            self?.onChange?()
        }
        listenToDevice()
    }

    public func stopListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners = []
        device = AudioObjectID(kAudioObjectUnknown)
        onChange = nil
    }

    /// Moves the volume and mute listeners to the current output.
    private func listenToDevice() {
        listeners.removeAll { listener in
            guard listener.object == device else { return false }
            listener.remove()
            return true
        }
        device = hardware.defaultOutput()
        for property in [AudioProperty.volume, .mute] {
            listen(to: device, property) { [weak self] in self?.onChange?() }
        }
    }

    private func listen(to object: AudioObjectID, _ property: AudioProperty, _ handler: @escaping @MainActor () -> Void) {
        guard let remove = hardware.listen(to: object, property, handler) else { return }
        listeners.append((object, remove))
    }
}
