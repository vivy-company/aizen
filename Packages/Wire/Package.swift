// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenWire",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenWire", targets: ["AizenWire"])],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.29.0")
    ],
    targets: [
        .target(
            name: "AizenWire",
            dependencies: [
                .product(name: "AizenCore", package: "Core"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            exclude: ["Protocol"]
        ),
        .testTarget(
            name: "AizenWireTests",
            dependencies: ["AizenWire", .product(name: "SwiftProtobuf", package: "swift-protobuf")],
            resources: [.copy("Fixtures")]
        )
    ]
)
