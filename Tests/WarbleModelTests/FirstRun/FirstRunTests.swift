import Foundation
import Testing
@testable import WarbleModel

@Test func theFirstRunWindowOpensOnANewInstall() {
    #expect(FirstRun.opens(storedKeys: []))
}

@Test func theFirstRunWindowNeverOpensTwice() {
    #expect(!FirstRun.opens(storedKeys: [FirstRun.shownKey]))
}

@Test func theFirstRunWindowStaysShutForSomeoneUpdatingWhoNeverOpenedSettings() {
    #expect(!FirstRun.opens(storedKeys: ["SUHasLaunchedBefore"]))
    #expect(!FirstRun.opens(storedKeys: ["SULastCheckTime", "SUEnableAutomaticChecks"]))
}

@Test func theFirstRunWindowStaysShutForSomeoneUpdatingWithASavedSetting() {
    for key in ["virtualTitle", "pauseDelay", "virtualNotch", "cardSize", "notchFont", "favouriteHeart"] {
        #expect(!FirstRun.opens(storedKeys: [key]), "\(key)")
    }
}

@Test func keysWarbleNeverStoresDontCountAsAnEarlierLaunch() {
    #expect(FirstRun.opens(storedKeys: ["NSWindow Frame Settings", "AppleLanguages"]))
}
