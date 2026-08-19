// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "Sync",
            targets: ["Sync"]
        ),
    ],
    dependencies: [
        .package(path: "../RimeEngine"),
    ],
    targets: [
        .target(
            name: "Sync",
            dependencies: [
                .product(name: "RimeEngine", package: "RimeEngine"),
            ],
            path: "Sources/Sync"
        ),
    ]
)