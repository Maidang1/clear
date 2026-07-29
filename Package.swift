// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Clear",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClearCore", targets: ["ClearCore"]),
        .library(name: "ClearMac", targets: ["ClearMac"]),
        .executable(name: "Clear", targets: ["ClearApp"])
    ],
    targets: [
        .target(
            name: "ClearCore",
            path: "Sources/ClearCore"
        ),
        .target(
            name: "ClearMac",
            dependencies: ["ClearCore"],
            path: "Sources/ClearMac",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "ClearApp",
            dependencies: ["ClearCore", "ClearMac"],
            path: "Sources/ClearApp"
        ),
        .testTarget(
            name: "ClearCoreTests",
            dependencies: ["ClearCore"],
            path: "Tests/ClearCoreTests"
        ),
        .testTarget(
            name: "ClearMacTests",
            dependencies: ["ClearMac"],
            path: "Tests/ClearMacTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
