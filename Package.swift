// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "oztam-validator-lib",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "OztamValidatorLib",
            targets: ["oztam-validator-lib"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "oztam-validator-lib",
            dependencies: []),
        .testTarget(
            name: "oztam-validator-libTests",
            dependencies: ["oztam-validator-lib"]),
    ]
)
