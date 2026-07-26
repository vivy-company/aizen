// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenStorage",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AizenStorage", targets: ["AizenStorage"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "AizenStorage", dependencies: [.product(name: "AizenCore", package: "Core")]),
        .testTarget(name: "AizenStorageTests", dependencies: ["AizenStorage", .product(name: "AizenCore", package: "Core")])
    ]
)
