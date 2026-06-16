// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoUp",
    platforms: [
        .macOS("13.3")
    ],
    products: [
        .executable(
            name: "AutoUp",
            targets: ["AutoUp"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.14.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.10.0"),
        .package(url: "https://github.com/PostHog/posthog-ios", from: "3.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0")
    ],
    targets: [
        .executableTarget(
            name: "AutoUp",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "AutoUpTests",
            dependencies: ["AutoUp"],
            path: "Tests"
        )
    ]
)