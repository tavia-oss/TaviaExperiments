// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "TaviaExperiments",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AppFeature",
            targets: ["AppFeature"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: []),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature"]),
    ]
)
