// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenCLIContracts",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AizenCLIContracts", targets: ["AizenCLIContracts"])],
    targets: [
        .target(
            name: "AizenCLIContracts",
            path: "Sources/AizenCLIContracts"
        ),
        .testTarget(
            name: "AizenCLIContractsTests",
            dependencies: ["AizenCLIContracts"],
            path: "Tests"
        )
    ]
)
