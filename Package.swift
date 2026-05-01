// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodingPlanKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CodingPlanAuth",
            targets: ["CodingPlanAuth"]
        ),
        .library(
            name: "CodingPlanCodex",
            targets: ["CodingPlanCodex"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/atom2ueki/SwiftWebServer.git", from: "0.3.1"),
    ],
    targets: [
        .target(
            name: "CodingPlanAuth",
            dependencies: [
                .product(name: "SwiftWebServer", package: "SwiftWebServer"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .target(
            name: "CodingPlanCodex",
            dependencies: ["CodingPlanAuth"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "CodingPlanAuthTests",
            dependencies: ["CodingPlanAuth"]
        ),
        .testTarget(
            name: "CodingPlanCodexTests",
            dependencies: ["CodingPlanCodex", "CodingPlanAuth"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
