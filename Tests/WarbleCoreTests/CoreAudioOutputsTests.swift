import Testing
@testable import WarbleCore

// The Mac's real sound hardware, so a runner may have no outputs at all. These check what holds either way; choosing
// an output isn't tested, since it would change the machine's sound settings.

@MainActor
@Test func theOutputsOfferedHaveDistinctIDs() {
    let ids = CoreAudioOutputs().all.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@MainActor
@Test func listeningStartsAndStopsWithoutOutputsChanging() {
    let outputs = CoreAudioOutputs()
    outputs.startListening {}
    outputs.startListening {}
    outputs.stopListening()
    outputs.stopListening()
}
