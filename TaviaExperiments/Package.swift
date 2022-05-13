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
            dependencies: [
                "PlaceGif",
                "PlaceImage",
                "PlaceObject",
                "PlaceVideo",
            ]),
        .target(name: "GifHelper"),
        .target(
            name: "PlaceGif",
            dependencies: ["GifHelper"],
            resources: [.process("Resources")]),
        .target(
            name: "PlaceImage",
            resources: [.process("Resources")]),
        .target(name: "PlaceObject"),
        .target(
            name: "PlaceVideo",
            resources: [.process("Resources")]),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature"]),
    ]
)
