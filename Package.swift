// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftCardanoTxBuilder",
    platforms: [
      .iOS(.v18), // bumped from v14: depends on swift-cardano-chain, now iOS 18
      .macOS(.v15),
      .watchOS(.v7),
      .tvOS(.v14),
    ],
    products: [
        .library(
            name: "SwiftCardanoTxBuilder",
            targets: ["SwiftCardanoTxBuilder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.11.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", from: "0.17.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-nacl.git", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-cips.git", from: "0.5.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", "5.7.0"..<"7.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftCardanoTxBuilder",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftNaCl", package: "swift-nacl"),
                .product(name: "Clibsodium", package: "swift-nacl"),
                // CIP-21 alone: the rest of swift-cardano-cips is not linked.
                .product(name: "SwiftCardanoCIP21", package: "swift-cardano-cips"),
                "BigInt",
            ]
        ),
        .testTarget(
            name: "SwiftCardanoTxBuilderTests",
            dependencies: ["SwiftCardanoTxBuilder", "BigInt"],
            resources: [
               .copy("data")
           ]
        ),
    ]
)
