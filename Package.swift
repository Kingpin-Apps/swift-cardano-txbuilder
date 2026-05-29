// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftCardanoTxBuilder",
    platforms: [
      .iOS(.v14),
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
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.4.3"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", from: "0.5.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-nacl.git", .upToNextMinor(from: "1.0.1")),
    ],
    targets: [
        .target(
            name: "SwiftCardanoTxBuilder",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftNaCl", package: "swift-nacl"),
                .product(name: "Clibsodium", package: "swift-nacl"),
            ]
        ),
        .testTarget(
            name: "SwiftCardanoTxBuilderTests",
            dependencies: ["SwiftCardanoTxBuilder"],
            resources: [
               .copy("data")
           ]
        ),
    ]
)
