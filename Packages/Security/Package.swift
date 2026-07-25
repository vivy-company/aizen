// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenSecurity",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AizenSecurity", targets: ["AizenSecurity"])],
    dependencies: [.package(path: "../Core"), .package(path: "../Wire")],
    targets: [
        .target(name: "AizenSecurity", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenWire", package: "Wire")
        ]),
        .testTarget(name: "AizenSecurityTests", dependencies: ["AizenSecurity"])
    ]
)
