// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenTestSupport",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenTestSupport", targets: ["AizenTestSupport"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire")],
    targets: [
        .target(name: "AizenTestSupport", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire")
        ]),
        .testTarget(name: "AizenTestSupportTests", dependencies: ["AizenTestSupport"])
    ]
)
