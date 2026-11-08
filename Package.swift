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
        .executableTarget(
            name: "SenseBar",
            path: "Sources/SenseBar",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "NowPlayingBridge",
            path: "Sources/NowPlayingBridge",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
