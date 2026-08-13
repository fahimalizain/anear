// swift-tools-version:5.9
import PackageDescription

// Command Line Tools without Xcode ship the Swift Testing framework only at
// this path, and SwiftPM does not add it to the module search path on its own.
// These flags are inert when an Xcode toolchain is in use (the framework is
// then part of the SDK), so they are safe for CI.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltDeveloperLib = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "anear",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "AnearCore",
            targets: ["AnearCore"]
        ),
        .executable(
            name: "Anear",
            targets: ["Anear"]
        ),
    ],
    targets: [
        .target(
            name: "AnearCore",
            path: "Sources/AnearCore"
        ),
        .executableTarget(
            name: "Anear",
            dependencies: ["AnearCore"],
            path: "Sources/Anear",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "AnearCoreTests",
            dependencies: ["AnearCore"],
            path: "Tests/AnearCoreTests",
            swiftSettings: [
                .unsafeFlags(["-F", cltFrameworks]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", cltFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", cltDeveloperLib,
                ]),
            ]
        ),
    ]
)
