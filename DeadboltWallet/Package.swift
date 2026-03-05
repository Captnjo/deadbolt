// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DeadboltWallet",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "Packages/DeadboltCore"),
        .package(path: "Packages/HardwareWallet"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "DeadboltApp",
            dependencies: [
                "DeadboltCore",
                .product(name: "HardwareWallet", package: "HardwareWallet", condition: .when(platforms: [.macOS])),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "App",
            exclude: ["iOS/Info.plist"],
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/DeadboltLogomark.png"),
                .copy("Resources/DeadboltLogotype.png"),
            ]
        ),
    ]
)
