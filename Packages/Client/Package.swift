// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenClient",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenClient", targets: ["AizenClient"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire"), .package(path: "../Transport")],
    targets: [
        .target(name: "AizenClient", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire"),
            .product(name: "AizenTransport", package: "Transport")
        ]),
        .testTarget(name: "AizenClientTests", dependencies: [
            "AizenClient",
            .product(name: "AizenTransport", package: "Transport"),
            .product(name: "AizenWire", package: "Wire")
        ])
    ]
)
