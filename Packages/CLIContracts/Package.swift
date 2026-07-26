// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenCLIContracts",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AizenCLIContracts", targets: ["AizenCLIContracts"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(
            name: "AizenCLIContracts",
            dependencies: [.product(name: "AizenCore", package: "Core")],
            path: "Sources/AizenCLIContracts"
        ),
        .testTarget(
            name: "AizenCLIContractsTests",
            dependencies: [
                "AizenCLIContracts",
                .product(name: "AizenCore", package: "Core")
            ],
            path: "Tests"
        )
    ]
)
