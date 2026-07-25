// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenFeatures",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AizenFeatures", targets: ["AizenFeatures"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Client")],
    targets: [
        .target(name: "AizenFeatures", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenClient", package: "Client")
        ]),
        .testTarget(name: "AizenFeaturesTests", dependencies: ["AizenFeatures"])
    ]
)
