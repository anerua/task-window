// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "task-window",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "task-window"
        ),
        .testTarget(
            name: "task-windowTests",
            dependencies: ["task-window"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
