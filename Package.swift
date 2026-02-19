// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChoirController",
    defaultLocalization: "en",
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
            exclude: [
                "cmudict.txt",          // Source lexicon (used by DictCompiler)
                "swe_lexicon.txt",      // Source lexicon (used by DictCompiler)
                "Info.plist",
            ],
            resources: [
                .process("Assets.xcassets"),
                .copy("AnimaleSounds"),
                .copy("en.choirdict"),
                .copy("sv.choirdict"),
                .copy("Robots.choir"),
                .process("Localizable.xcstrings")
            ]
        ),
        .executableTarget(
            name: "DictCompiler",
            path: "Sources/DictCompiler"
        ),
        .testTarget(
            name: "ChoirControllerTests",
            dependencies: ["ChoirController"]),
    ]
)
