import Foundation
import Testing
@testable import WarbleCore
import WarbleModel

@Test func theOfferOfOnePointOhToABetaNamesBothVersions() {
    let offer = UpdateOffer(version: "1.0.0", build: "600", installedVersion: "0.1.0-beta.26", installedBuild: "560", downloadSize: 6_000_000)
    #expect(UpdateWindowLabel.offerTitle(offer) == "Warble 1.0.0 is ready")
    #expect(UpdateWindowLabel.offerMessage(offer).hasPrefix("You have 0.1.0-beta.26. The download is "))
}
