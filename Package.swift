// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiscordRPMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiscordRPMac", targets: ["DiscordRPMac"]),
        .library(name: "DiscordRP", targets: ["DiscordRP"]),
    ],
    targets: [
        // Protocol/model/engine: strict Swift 6 concurrency.
        .target(name: "DiscordRP"),
        // SwiftUI + AppKit glue: language mode 5 (SwiftUI/NSApp bridging is not
        // concurrency-clean yet); the DiscordRP API it consumes is already checked.
        .executableTarget(
            name: "DiscordRPMac",
            dependencies: ["DiscordRP"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DiscordRPTests", dependencies: ["DiscordRP"]),
    ]
)
