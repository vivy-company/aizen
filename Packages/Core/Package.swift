// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenCore", targets: ["AizenCore"])],
    targets: [
        .target(name: "AizenCore"),
        .testTarget(name: "AizenCoreTests", dependencies: ["AizenCore"])
    ]
)
