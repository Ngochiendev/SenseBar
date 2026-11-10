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
    targets: [
        .target(
            name: "SenseBarAudioBridge",
            path: "Sources/SenseBarAudioBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "SenseBar",
            dependencies: ["SenseBarAudioBridge"],
            path: "Sources/SenseBar"
        ),
        .target(
            name: "NowPlayingBridge",
            path: "Sources/NowPlayingBridge"
        )
    ],
    swiftLanguageModes: [.v6]
)
