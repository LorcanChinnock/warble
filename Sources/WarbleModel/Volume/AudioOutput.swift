import Foundation

/// A sound output the Mac can play through, as Core Audio describes it.
public struct AudioOutput: Identifiable, Equatable, Sendable {
    /// Core Audio's device ID.
    public let id: UInt32
    public let name: String
    public let transport: Transport
    /// Whether it's the built-in headphone jack rather than the speakers, from the device's data source.
    public let isHeadphoneJack: Bool
    public let hasOutputChannels: Bool
    /// `kAudioDevicePropertyDeviceCanBeDefaultDevice`: false for most virtual devices, such as Teams' loopback driver.
    public let canBeDefault: Bool
    public let isHidden: Bool

    public init(id: UInt32, name: String, transport: Transport, isHeadphoneJack: Bool = false, hasOutputChannels: Bool = true, canBeDefault: Bool = true, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isHeadphoneJack = isHeadphoneJack
        self.hasOutputChannels = hasOutputChannels
        self.canBeDefault = canBeDefault
        self.isHidden = isHidden
    }

    /// How a device connects, from `kAudioDevicePropertyTransportType`.
    public enum Transport: Equatable, Sendable {
        case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, virtual, aggregate, other

        /// From the four-character code Core Audio reports, such as `bltn`.
        public init(code: UInt32) {
            switch code {
            case fourCharCode("bltn"): self = .builtIn
            case fourCharCode("blue"), fourCharCode("blea"): self = .bluetooth
            case fourCharCode("usb "): self = .usb
            case fourCharCode("hdmi"): self = .hdmi
            case fourCharCode("dprt"): self = .displayPort
            case fourCharCode("airp"): self = .airPlay
            case fourCharCode("thun"): self = .thunderbolt
            case fourCharCode("virt"): self = .virtual
            case fourCharCode("grup"), fourCharCode("cagg"): self = .aggregate
            default: self = .other
            }
        }
    }

    /// The outputs to offer, as the Sound settings list them: those with output channels that can be the default and
    /// aren't hidden, built-in first and the rest by name.
    public static func choices(_ devices: [AudioOutput]) -> [AudioOutput] {
        devices
            .filter { $0.hasOutputChannels && $0.canBeDefault && !$0.isHidden }
            .sorted { lhs, rhs in
                if (lhs.transport == .builtIn) != (rhs.transport == .builtIn) { return lhs.transport == .builtIn }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// The SF Symbol that pictures it, as Control Centre's sound menu does.
    public var symbol: String {
        switch transport {
        case .builtIn:
            if isHeadphoneJack { "headphones" }
            else if name.contains("MacBook") { "laptopcomputer" }
            else { "desktopcomputer" }
        case .bluetooth:
            if name.localizedCaseInsensitiveContains("AirPods Max") { "airpods.max" }
            else if name.localizedCaseInsensitiveContains("AirPods Pro") { "airpods.pro" }
            else if name.localizedCaseInsensitiveContains("AirPods") { "airpods" }
            else { "headphones" }
        case .hdmi, .displayPort: "display"
        case .airPlay: "airplayaudio"
        case .usb, .thunderbolt, .virtual, .aggregate, .other: "hifispeaker"
        }
    }
}

private func fourCharCode(_ code: String) -> UInt32 {
    code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
}
