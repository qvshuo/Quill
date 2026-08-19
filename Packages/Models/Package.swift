// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Models",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "Models",
            targets: ["Models"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Models",
            path: "Sources/Models"
        ),
    ]
)
