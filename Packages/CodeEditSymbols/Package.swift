// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "CodeEditSymbols",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "CodeEditSymbols",
            targets: ["CodeEditSymbols"]),
    ],
    dependencies: [
        .package(
            name: "SnapshotTesting",
            url: "https://github.com/pointfreeco/swift-snapshot-testing.git",
            from: "1.9.0"
        ),
    ],
    targets: [
        .target(
            name: "CodeEditSymbols",
            dependencies: []
        ),
        .testTarget(
            name: "CodeEditSymbolsTests",
            dependencies: [
                "CodeEditSymbols",
                "SnapshotTesting"
            ]
        ),
    ]
)
