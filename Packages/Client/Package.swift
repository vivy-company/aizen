// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenClient",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AizenClient", targets: ["AizenClient"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire")],
    targets: [
        .target(name: "AizenClient", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire")
        ]),
        .testTarget(name: "AizenClientTests", dependencies: ["AizenClient"])
    ]
)
