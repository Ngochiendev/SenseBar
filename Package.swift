// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SenseBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SenseBar", targets: ["SenseBar"]),
        .library(name: "SenseBarNowPlaying", type: .dynamic, targets: ["NowPlayingBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(
            name: "SenseBarAudioBridge",
            path: "Sources/SenseBarAudioBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "SenseBar",
            dependencies: ["SenseBarAudioBridge", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SenseBar",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(
            name: "NowPlayingBridge",
            path: "Sources/NowPlayingBridge"
        )
    ],
    swiftLanguageModes: [.v6]
)
