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
        .library(
            name: "ChargeWattControl",
            targets: ["ChargeWattControl"]
        ),
        .executable(
            name: "ChargeWattMenu",
            targets: ["ChargeWattMenu"]
        ),
        .executable(
            name: "ChargeWattMenuDaemon",
            targets: ["ChargeWattMenuDaemon"]
        )
    ],
    dependencies: [
        .package(
            path: "Vendor/Battery-Toolkit-SP"
        )
    ],
    targets: [
        .target(
            name: "ChargeWattCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "ChargeWattControl",
            dependencies: [
                "ChargeWattCore",
                .product(name: "BatteryToolkit", package: "Battery-Toolkit-SP")
            ]
        ),
        .executableTarget(
            name: "ChargeWattMenu",
            dependencies: [
                "ChargeWattCore",
                "ChargeWattControl"
            ],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "ChargeWattMenuDaemon",
            dependencies: [
                .product(name: "BatteryToolkit", package: "Battery-Toolkit-SP")
            ]
        ),
        .testTarget(
            name: "ChargeWattCoreTests",
            dependencies: ["ChargeWattCore"]
        ),
        .testTarget(
            name: "ChargeWattControlTests",
            dependencies: ["ChargeWattControl"]
        )
    ]
)
