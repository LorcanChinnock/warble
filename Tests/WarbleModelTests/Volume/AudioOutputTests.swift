import Testing
@testable import WarbleModel

private let speakers = AudioOutput(id: 1, name: "MacBook Air Speakers", transport: .builtIn)

@Test func thePickerHidesDevicesThatCantPlayOrBeTheDefault() {
    let devices = [
        speakers,
        AudioOutput(id: 2, name: "Microsoft Teams Audio", transport: .virtual, canBeDefault: false),
        AudioOutput(id: 3, name: "MacBook Air Microphone", transport: .builtIn, hasOutputChannels: false),
        AudioOutput(id: 4, name: "Hidden Driver", transport: .virtual, isHidden: true),
    ]
    #expect(AudioOutput.choices(devices) == [speakers])
}

@Test func builtInSpeakersComeFirstAndTheRestByName() {
    let airPods = AudioOutput(id: 5, name: "Lorcan's AirPods Pro", transport: .bluetooth)
    let display = AudioOutput(id: 6, name: "dell U2723QE", transport: .displayPort)
    #expect(AudioOutput.choices([airPods, display, speakers]).map(\.id) == [1, 6, 5])
}

@Test func transportCodesAreReadFromCoreAudiosFourCharacterCodes() {
    #expect(AudioOutput.Transport(code: 0x626C_746E) == .builtIn) // bltn
    #expect(AudioOutput.Transport(code: 0x626C_7565) == .bluetooth) // blue
    #expect(AudioOutput.Transport(code: 0x7573_6220) == .usb) // "usb "
    #expect(AudioOutput.Transport(code: 0x6169_7270) == .airPlay) // airp
    #expect(AudioOutput.Transport(code: 0) == .other)
}

@Test func eachOutputHasTheSymbolControlCentreShows() {
    #expect(speakers.symbol == "laptopcomputer")
    #expect(AudioOutput(id: 1, name: "iMac Speakers", transport: .builtIn).symbol == "desktopcomputer")
    #expect(AudioOutput(id: 1, name: "External Headphones", transport: .builtIn, isHeadphoneJack: true).symbol == "headphones")
    #expect(AudioOutput(id: 1, name: "Lorcan's AirPods Pro", transport: .bluetooth).symbol == "airpods.pro")
    #expect(AudioOutput(id: 1, name: "AirPods Max", transport: .bluetooth).symbol == "airpods.max")
    #expect(AudioOutput(id: 1, name: "AirPods", transport: .bluetooth).symbol == "airpods")
    #expect(AudioOutput(id: 1, name: "WH-1000XM5", transport: .bluetooth).symbol == "headphones")
    #expect(AudioOutput(id: 1, name: "LG HDR 4K", transport: .hdmi).symbol == "display")
    #expect(AudioOutput(id: 1, name: "Scarlett 2i2", transport: .usb).symbol == "hifispeaker")
}
