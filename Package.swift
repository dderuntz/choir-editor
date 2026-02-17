// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChoirController",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "ChoirController",
            targets: ["ChoirController"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orchetect/MIDIKit.git", from: "0.9.5")
    ],
    targets: [
        .executableTarget(
            name: "ChoirController",
            dependencies: [
                .product(name: "MIDIKit", package: "MIDIKit")
            ],
            resources: [
                .process("Assets.xcassets"),
                .copy("AnimaleSounds"),
                .copy("cmudict.txt")
            ]
        ),
        .testTarget(
            name: "ChoirControllerTests",
            dependencies: ["ChoirController"]),
    ]
)
