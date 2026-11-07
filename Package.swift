// swift-tools-version: 6.0
import PackageDescription

// The app builds from Warble.xcodeproj. This package holds only WarbleModel, which needs only Foundation, so CI's linux
// check and `make test-linux` build and test it on Linux and keep it portable.
let package = Package(
    name: "Warble",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "WarbleModel"),
        // The tests read their recorded fixtures from the source tree.
        .testTarget(name: "WarbleModelTests", dependencies: ["WarbleModel"], exclude: ["Playback/Fixtures"]),
    ]
)
