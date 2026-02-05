// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChoirController",
    platforms: [
        .macOS(.v13)
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
            ]
            // Removed resources: [.process("Info.plist")] as it causes build error for executables
        ),
        .testTarget(
            name: "ChoirControllerTests",
            dependencies: ["ChoirController"]),
    ]
)
