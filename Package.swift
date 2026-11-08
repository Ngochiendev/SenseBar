// swift-tools-version: 5.9

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
            path: "Sources/SenseBar"
        ),
        .target(
            name: "NowPlayingBridge",
            path: "Sources/NowPlayingBridge"
        )
    ]
)
