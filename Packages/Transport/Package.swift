// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenTransport",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenTransport", targets: ["AizenTransport"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire")],
    targets: [
        .target(name: "AizenTransport", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire")
        ]),
        .testTarget(name: "AizenTransportTests", dependencies: ["AizenTransport"])
    ]
)
