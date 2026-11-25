// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgyUsageMenubar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgyUsageCore", targets: ["AgyUsageCore"]),
        .executable(name: "AgyUsageMenubar", targets: ["AgyUsageMenubar"])
    ],
    targets: [
        .target(
            name: "AgyUsageCore",
            path: "Sources/AgyUsageCore"
        ),
        .executableTarget(
            name: "AgyUsageMenubar",
            dependencies: ["AgyUsageCore"],
            path: "Sources/AgyUsageMenubar"
        ),
        .testTarget(
            name: "AgyUsageCoreTests",
            dependencies: ["AgyUsageCore"],
            path: "Tests/AgyUsageCoreTests"
        )
    ]
)
