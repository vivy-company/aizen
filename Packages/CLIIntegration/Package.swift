// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenCLIIntegration",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Client"),
        .package(path: "../Core"),
        .package(path: "../Host"),
        .package(path: "../Storage"),
        .package(path: "../Transport"),
        .package(path: "../Wire")
    ],
    targets: [
        .target(
            name: "AizenCLIIntegration",
            dependencies: [
                .product(name: "AizenClient", package: "Client"),
                .product(name: "AizenCore", package: "Core"),
                .product(name: "AizenWire", package: "Wire")
            ],
            path: "Sources/AizenCLIIntegration"
        ),
        .testTarget(
            name: "AizenCLIIntegrationTests",
            dependencies: [
                "AizenCLIIntegration",
                .product(name: "AizenClient", package: "Client"),
                .product(name: "AizenCore", package: "Core"),
                .product(name: "AizenHost", package: "Host"),
                .product(name: "AizenStorage", package: "Storage"),
                .product(name: "AizenTransport", package: "Transport")
            ]
        )
    ]
)
