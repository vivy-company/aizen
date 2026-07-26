// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenSecurity",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenSecurity", targets: ["AizenSecurity"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire"), .package(path: "../Transport")],
    targets: [
        .target(name: "AizenSecurity", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire"),
            .product(name: "AizenTransport", package: "Transport")
        ]),
        .testTarget(name: "AizenSecurityTests", dependencies: ["AizenSecurity", .product(name: "AizenWire", package: "Wire")])
    ]
)
