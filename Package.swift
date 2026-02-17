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
        .package(url: "https://github.com/orchetect/MIDIKit.git", from: "0.9.5"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ChoirController",
            dependencies: [
                .product(name: "MIDIKit", package: "MIDIKit"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ],
            resources: [
                .process("Assets.xcassets"),
                .copy("AnimaleSounds"),
                .copy("cmudict.txt"),
                .copy("Robots.choir")
            ]
        ),
        .testTarget(
            name: "ChoirControllerTests",
            dependencies: ["ChoirController"]),
    ]
)
