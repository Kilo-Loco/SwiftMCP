// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMCP",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftMCP",
            targets: ["SwiftMCP"]
        ),
        .library(
            name: "SwiftMCPTools",
            targets: ["SwiftMCPTools"]
        ),
        .library(
            name: "SwiftMCPTransports",
            targets: ["SwiftMCPTransports"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftMCP",
            dependencies: []
        ),
        .target(
            name: "SwiftMCPTools",
            dependencies: ["SwiftMCP"]
        ),
        .target(
            name: "SwiftMCPTransports",
            dependencies: ["SwiftMCP"]
        ),
        .testTarget(
            name: "SwiftMCPTests",
            dependencies: ["SwiftMCP", "SwiftMCPTools", "SwiftMCPTransports"]
        ),
    ]
)
