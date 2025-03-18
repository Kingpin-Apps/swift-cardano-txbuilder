// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftCardanoTxBuilder",
    platforms: [
      .iOS(.v14),
      .macOS(.v13),
      .watchOS(.v7),
      .tvOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftCardanoTxBuilder",
            targets: ["SwiftCardanoTxBuilder"]),
    ],
    dependencies: [
//        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", branch: "main"),
//        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", branch: "main"),
        .package(path: "/Users/hadderley/Projects/AGL/Kingpin-Apps/swift-cardano-core"),
        .package(path: "/Users/hadderley/Projects/AGL/Kingpin-Apps/swift-cardano-chain"),
        .package(url: "https://github.com/Kingpin-Apps/swift-ncal.git", .upToNextMinor(from: "0.1.4")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftCardanoTxBuilder",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftNcal", package: "swift-ncal"),
                .product(name: "Clibsodium", package: "swift-ncal"),
            ]
        ),
        .testTarget(
            name: "SwiftCardanoTxBuilderTests",
            dependencies: ["SwiftCardanoTxBuilder"]
        ),
    ]
)
