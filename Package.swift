// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "TomatoBarFlow",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "TomatoBarFlow", targets: ["TomatoBarFlow"]),
    ],
    targets: [
        .target(
            name: "TomatoBarFlow",
            path: "TomatoBarFlow"
        ),
        .testTarget(
            name: "TomatoBarFlowTests",
            dependencies: ["TomatoBarFlow"],
            path: "TomatoBarFlowTests"
        ),
    ]
)
