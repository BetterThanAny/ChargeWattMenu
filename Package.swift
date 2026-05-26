// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChargeWattMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ChargeWattCore",
            targets: ["ChargeWattCore"]
        ),
        .executable(
            name: "ChargeWattMenu",
            targets: ["ChargeWattMenu"]
        )
    ],
    targets: [
        .target(
            name: "ChargeWattCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ChargeWattMenu",
            dependencies: ["ChargeWattCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "ChargeWattCoreTests",
            dependencies: ["ChargeWattCore"]
        )
    ]
)
