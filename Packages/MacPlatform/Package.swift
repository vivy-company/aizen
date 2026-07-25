// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenMacPlatform",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AizenMacPlatform", targets: ["AizenMacPlatform"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "AizenMacPlatform", dependencies: [.product(name: "AizenCore", package: "Core")]),
        .testTarget(name: "AizenMacPlatformTests", dependencies: ["AizenMacPlatform"])
    ]
)
