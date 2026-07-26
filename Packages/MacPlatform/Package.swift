// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenMacPlatform",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AizenMacPlatform", targets: ["AizenMacPlatform"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Client"),
        .package(path: "../Host"),
        .package(path: "../Storage"),
        .package(path: "../Security"),
        .package(path: "../Transport"),
        .package(path: "../Wire"),
        .package(url: "https://github.com/wiedymi/swift-acp", revision: "9498537769d1309b6519fbb87d0c22fcf9317f3e")
    ],
    targets: [
        .target(name: "AizenMacPlatform", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenClient", package: "Client"),
            .product(name: "AizenHost", package: "Host"),
            .product(name: "AizenStorage", package: "Storage"),
            .product(name: "AizenSecurity", package: "Security"),
            .product(name: "AizenTransport", package: "Transport"),
            .product(name: "ACP", package: "swift-acp")
        ]),
        .testTarget(name: "AizenMacPlatformTests", dependencies: [
            "AizenMacPlatform",
            .product(name: "AizenHost", package: "Host"),
            .product(name: "AizenSecurity", package: "Security"),
            .product(name: "AizenTransport", package: "Transport"),
            .product(name: "AizenWire", package: "Wire"),
            .product(name: "ACP", package: "swift-acp")
        ])
    ]
)
