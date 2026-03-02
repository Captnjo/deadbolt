// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DeadboltCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DeadboltCore", targets: ["DeadboltCore"]),
    ],
    targets: [
        .target(
            name: "DeadboltCore",
            path: "Sources/DeadboltCore"
        ),
        .testTarget(
            name: "DeadboltCoreTests",
            dependencies: ["DeadboltCore"],
            path: "Tests/DeadboltCoreTests"
        ),
    ]
)
