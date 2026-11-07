// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SenseBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SenseBar",
            path: "Sources/SenseBar",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
