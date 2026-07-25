// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenHost",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AizenHost", targets: ["AizenHost"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire")],
    targets: [
        .target(name: "AizenHost", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire")
        ]),
        .testTarget(name: "AizenHostTests", dependencies: ["AizenHost"])
    ]
)
