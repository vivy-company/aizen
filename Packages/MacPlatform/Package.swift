// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenMacPlatform",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AizenMacPlatform", targets: ["AizenMacPlatform"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Host"),
        .package(url: "https://github.com/wiedymi/swift-acp", revision: "9498537769d1309b6519fbb87d0c22fcf9317f3e")
    ],
    targets: [
        .target(name: "AizenMacPlatform", dependencies: [
            .product(name: "AizenCore", package: "Core"),
            .product(name: "AizenHost", package: "Host"),
            .product(name: "ACP", package: "swift-acp")
        ]),
        .testTarget(name: "AizenMacPlatformTests", dependencies: [
            "AizenMacPlatform",
            .product(name: "AizenHost", package: "Host"),
            .product(name: "ACP", package: "swift-acp")
        ])
    ]
)
