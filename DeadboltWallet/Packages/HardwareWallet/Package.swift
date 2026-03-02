// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HardwareWallet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HardwareWallet", targets: ["HardwareWallet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/armadsen/ORSSerialPort.git", from: "2.1.0"),
        .package(path: "../DeadboltCore"),
    ],
    targets: [
        .target(
            name: "HardwareWallet",
            dependencies: [
                .product(name: "ORSSerial", package: "ORSSerialPort"),
                "DeadboltCore",
            ],
            path: "Sources/HardwareWallet"
        ),
        .testTarget(
            name: "HardwareWalletTests",
            dependencies: ["HardwareWallet"],
            path: "Tests/HardwareWalletTests"
        ),
    ]
)
