// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodingPlanAuthKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CodingPlanAuthKit",
            targets: ["CodingPlanAuthKit"]
        ),
        .library(
            name: "CodingPlanCodex",
            targets: ["CodingPlanCodex"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/atom2ueki/SwiftWebServer.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "CodingPlanAuthKit",
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
            dependencies: ["CodingPlanAuthKit"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "CodingPlanAuthKitTests",
            dependencies: ["CodingPlanAuthKit"]
        ),
        .testTarget(
            name: "CodingPlanCodexTests",
            dependencies: ["CodingPlanCodex", "CodingPlanAuthKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
