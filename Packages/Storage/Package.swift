// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenStorage",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AizenStorage", targets: ["AizenStorage"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Security")],
    targets: [
        .target(name: "AizenStorage", dependencies: [.product(name: "AizenCore", package: "Core"), .product(name: "AizenSecurity", package: "Security")]),
        .testTarget(name: "AizenStorageTests", dependencies: ["AizenStorage", .product(name: "AizenCore", package: "Core"), .product(name: "AizenSecurity", package: "Security")])
    ]
)
