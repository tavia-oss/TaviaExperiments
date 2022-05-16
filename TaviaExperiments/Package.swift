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
                "DetectAndCropColor",
                "DetectCropAndCopyHumanMovements",
                "DetectCropAndPlaceAlphanumeric",
                "DetectCropAndPlaceObject",
                "PlaceGif",
                "PlaceImage",
                "PlaceObject",
                "PlaceVideo",
            ]),
        .target(name: "ColorHelper"),
        .target(
            name: "DetectAndCropColor",
            dependencies: ["ColorHelper", "TransformHelper"]),
        .target(
            name: "DetectCropAndCopyHumanMovements",
            resources: [.process("Metal/Shaders.metal")]),
        .target(name: "DetectCropAndPlaceAlphanumeric"),
        .target(
            name: "DetectCropAndPlaceObject",
            dependencies: ["TransformHelper"],
            resources: [.process("Resources")]),
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
        .target(name: "TransformHelper"),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature"]),
    ]
)
