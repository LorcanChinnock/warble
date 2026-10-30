import CoreAudio
import Testing
@testable import WarbleCore

@MainActor
private final class FakeHardware: AudioHardware {
    struct Key: Hashable {
        var object: AudioObjectID
        var property: AudioProperty
    }

    var output: AudioObjectID = 10
    var floats: [Key: Float32] = [:]
    var uint32s: [Key: UInt32] = [:]
    var settable: Set<Key> = []
    var handlers: [Key: [Int: @MainActor () -> Void]] = [:]
    var failsToListen = false
    private var nextID = 0

    var listenerCount: Int { handlers.values.reduce(0) { $0 + $1.count } }

    func defaultOutput() -> AudioObjectID { output }
    func isSettable(_ object: AudioObjectID, _ property: AudioProperty) -> Bool {
        settable.contains(Key(object: object, property: property))
    }
    func float(_ object: AudioObjectID, _ property: AudioProperty) -> Float32? { floats[Key(object: object, property: property)] }
    func uint32(_ object: AudioObjectID, _ property: AudioProperty) -> UInt32? { uint32s[Key(object: object, property: property)] }
    func set(_ object: AudioObjectID, _ property: AudioProperty, float: Float32) { floats[Key(object: object, property: property)] = float }
    func set(_ object: AudioObjectID, _ property: AudioProperty, uint32: UInt32) { uint32s[Key(object: object, property: property)] = uint32 }

    func listen(to object: AudioObjectID, _ property: AudioProperty, _ handler: @escaping @MainActor () -> Void) -> (() -> Void)? {
        guard !failsToListen else { return nil }
        let key = Key(object: object, property: property)
        nextID += 1
        let id = nextID
        handlers[key, default: [:]][id] = handler
        return { [weak self] in
            MainActor.assumeIsolated { _ = self?.handlers[key]?.removeValue(forKey: id) }
        }
    }

    func fire(_ object: AudioObjectID, _ property: AudioProperty) {
        for handler in handlers[Key(object: object, property: property)]?.values.map({ $0 }) ?? [] {
            handler()
        }
    }

    /// A Mac whose output `output` has a volume and a mute switch.
    func addOutput(_ id: AudioObjectID, volume: Float32 = 0.5, muted: Bool = false) {
        floats[Key(object: id, property: .volume)] = volume
        uint32s[Key(object: id, property: .mute)] = muted ? 1 : 0
        settable.insert(Key(object: id, property: .volume))
        settable.insert(Key(object: id, property: .mute))
    }
}

private let system = AudioObjectID(kAudioObjectSystemObject)

@MainActor
@Test func theVolumeIsTheOutputsVolume() {
    let hardware = FakeHardware()
    hardware.addOutput(10, volume: 0.25)
    #expect(SystemVolume(hardware: hardware).volume == 0.25)
}

@MainActor
@Test func anOutputWithNoSettableVolumeHasNoVolume() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    hardware.settable.remove(.init(object: 10, property: .volume))
    #expect(SystemVolume(hardware: hardware).volume == nil)
}

@MainActor
@Test func aVolumeThatCannotBeReadIsNoVolume() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    hardware.floats[.init(object: 10, property: .volume)] = nil
    #expect(SystemVolume(hardware: hardware).volume == nil)
}

@MainActor
@Test func isMutedReadsTheMuteSwitch() {
    let hardware = FakeHardware()
    hardware.addOutput(10, muted: true)
    let volume = SystemVolume(hardware: hardware)
    #expect(volume.isMuted)
    hardware.uint32s[.init(object: 10, property: .mute)] = 0
    #expect(!volume.isMuted)
}

@MainActor
@Test func anOutputWithNoMuteSwitchIsNotMuted() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    hardware.uint32s[.init(object: 10, property: .mute)] = nil
    #expect(!SystemVolume(hardware: hardware).isMuted)
}

@MainActor
@Test(arguments: [(-0.5, Float32(0)), (0.4, 0.4), (1.7, 1)])
func settingTheVolumeKeepsItBetweenZeroAndOne(requested: Double, applied: Float32) {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    SystemVolume(hardware: hardware).set(requested)
    #expect(hardware.floats[.init(object: 10, property: .volume)] == applied)
}

@MainActor
@Test func settingAboveSilenceUnmutes() {
    let hardware = FakeHardware()
    hardware.addOutput(10, muted: true)
    SystemVolume(hardware: hardware).set(0.3)
    #expect(hardware.uint32s[.init(object: 10, property: .mute)] == 0)
}

@MainActor
@Test func settingSilenceLeavesTheMuteSwitchAlone() {
    let hardware = FakeHardware()
    hardware.addOutput(10, muted: true)
    SystemVolume(hardware: hardware).set(0)
    #expect(hardware.uint32s[.init(object: 10, property: .mute)] == 1)
}

@MainActor
@Test func aMuteSwitchThatCannotBeSetStaysAsItIs() {
    let hardware = FakeHardware()
    hardware.addOutput(10, muted: true)
    hardware.settable.remove(.init(object: 10, property: .mute))
    SystemVolume(hardware: hardware).set(0.3)
    #expect(hardware.uint32s[.init(object: 10, property: .mute)] == 1)
}

@MainActor
@Test func listeningWatchesTheOutputsVolumeAndMuteAndTheDefaultOutput() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    let volume = SystemVolume(hardware: hardware)
    var changes = 0
    volume.startListening { changes += 1 }
    #expect(hardware.listenerCount == 3)
    hardware.fire(10, .volume)
    hardware.fire(10, .mute)
    #expect(changes == 2)
}

@MainActor
@Test func aNewDefaultOutputMovesTheListenersAndReportsAChange() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    hardware.addOutput(20)
    let volume = SystemVolume(hardware: hardware)
    var changes = 0
    volume.startListening { changes += 1 }
    hardware.output = 20
    hardware.fire(system, .defaultOutput)
    #expect(changes == 1)
    #expect(hardware.listenerCount == 3)
    hardware.fire(10, .volume)
    #expect(changes == 1)
    hardware.fire(20, .volume)
    #expect(changes == 2)
}

@MainActor
@Test func stoppingRemovesEveryListener() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    let volume = SystemVolume(hardware: hardware)
    var changes = 0
    volume.startListening { changes += 1 }
    volume.stopListening()
    #expect(hardware.listenerCount == 0)
    hardware.fire(10, .volume)
    #expect(changes == 0)
}

@MainActor
@Test func listeningAgainReplacesTheEarlierListeners() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    let volume = SystemVolume(hardware: hardware)
    var first = 0
    var second = 0
    volume.startListening { first += 1 }
    volume.startListening { second += 1 }
    #expect(hardware.listenerCount == 3)
    hardware.fire(10, .volume)
    #expect(first == 0)
    #expect(second == 1)
}

@MainActor
@Test func listenersThatCannotBeAddedAreSkipped() {
    let hardware = FakeHardware()
    hardware.addOutput(10)
    hardware.failsToListen = true
    let volume = SystemVolume(hardware: hardware)
    volume.startListening {}
    volume.stopListening()
    #expect(hardware.listenerCount == 0)
}
