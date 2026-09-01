// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevPorts",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DevPorts",
            path: "Sources/DevPorts",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
