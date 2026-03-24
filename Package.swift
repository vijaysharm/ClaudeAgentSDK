// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeAgentSDK",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "ClaudeAgentSDK", targets: ["ClaudeAgentSDK"]),
    ],
    targets: [
        .target(
            name: "ClaudeAgentSDK",
            path: "Sources/ClaudeAgentSDK"
        ),
        .testTarget(
            name: "ClaudeAgentSDKTests",
            dependencies: ["ClaudeAgentSDK"],
            path: "Tests/ClaudeAgentSDKTests"
        ),
    ]
)
