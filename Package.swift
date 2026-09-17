// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "NotchIsland", targets: ["NotchIsland"]),
        .library(name: "NotchMediaBridge", type: .dynamic, targets: ["MediaBridge"]),
    ],
    targets: [
        .target(
            name: "MediaBridge",
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        .executableTarget(
            name: "NotchIsland",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NotchIslandTests",
            dependencies: ["NotchIsland"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
