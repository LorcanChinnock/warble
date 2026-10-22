// swift-tools-version: 6.0
// A stand-in music player to record for Warble's docs. Not part of Warble's build; see README.md.
import PackageDescription

let package = Package(
    name: "WarbleDemo",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "WarbleDemo")]
)
