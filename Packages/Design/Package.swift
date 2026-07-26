// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AizenDesign",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AizenDesign", targets: ["AizenDesign"])],
    targets: [
        .target(name: "AizenDesign"),
        .testTarget(name: "AizenDesignTests", dependencies: ["AizenDesign"])
    ]
)
