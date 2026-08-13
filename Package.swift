// swift-tools-version:5.9
import PackageDescription

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
            path: "Tests/AnearCoreTests"
        ),
    ]
)
