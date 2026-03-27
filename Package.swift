// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartiecoinWallet",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SmartiecoinWallet",
            targets: ["SmartiecoinWallet"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", exact: "0.10.0")
    ],
    targets: [
        .target(
            name: "SmartiecoinWallet",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift")
            ],
            path: "SmartiecoinWallet",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("WALLET_MODE_SPV")
            ],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security")
            ]
        )
    ]
)
