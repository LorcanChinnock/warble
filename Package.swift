// swift-tools-version: 6.0
import PackageDescription

// WarbleModel needs only Foundation, so CI builds and tests it on Linux. Everything else needs Apple frameworks.
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "WarbleModel"),
    // The tests read their recorded fixtures from the source tree.
    .testTarget(name: "WarbleModelTests", dependencies: ["WarbleModel"], exclude: ["Lyrics/Fixtures", "Playback/Fixtures"]),
]

#if os(macOS)
// Every build extracts the strings the app shows into .build/stringsdata, one folder per target since two targets can
// have files of the same name. scripts/strings.sh syncs them into Resources/Localizable.xcstrings.
func extractingStrings(_ target: String) -> [SwiftSetting] {
    let path = "\(Context.packageDirectory)/.build/stringsdata/\(target)"
    return [.unsafeFlags(["-emit-localized-strings", "-emit-localized-strings-path", path])]
}

dependencies += [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
]
targets += [
    .target(name: "WarbleCore", dependencies: ["WarbleModel"], swiftSettings: extractingStrings("WarbleCore")),
    .executableTarget(
        name: "Warble",
        dependencies: ["WarbleCore", .product(name: "Sparkle", package: "Sparkle")],
        swiftSettings: extractingStrings("Warble"),
        // bundle.sh copies Sparkle.framework into Contents/Frameworks.
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    // The `warble` command. bundle.sh copies it into the app as warble-cli: a "warble" there would collide with the app's own
    // Warble executable on a case-insensitive volume. It talks to the running app over a socket, so it needs only WarbleModel.
    .executableTarget(name: "WarbleCLI", dependencies: ["WarbleModel"]),
    .testTarget(name: "WarbleCoreTests", dependencies: ["WarbleCore"]),
]
#endif

let package = Package(
    name: "Warble",
    platforms: [.macOS(.v15)],
    dependencies: dependencies,
    targets: targets
)
