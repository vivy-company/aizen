// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenHost",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AizenHost", targets: ["AizenHost"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire"), .package(path: "../Storage"), .package(path: "../Transport")],
    targets: [
        .target(name: "AizenHost", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire"),
            .product(name: "AizenStorage", package: "Storage"),
            .product(name: "AizenTransport", package: "Transport")
        ]),
        .testTarget(name: "AizenHostTests", dependencies: [
            "AizenHost",
            .product(name: "AizenTransport", package: "Transport")
        ])
    ]
)
