import Foundation

/// Work `reduce` asks for outside the state, as data, so a test can check it was asked for and the app target carries it
/// out. Cases arrive with the features that need them.
public enum AppEffect: Equatable, Sendable {}
