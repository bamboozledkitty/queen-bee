// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QueenBeeCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "QueenBeeCore", targets: ["QueenBeeCore"])],
    targets: [
        .target(name: "QueenBeeCore"),
        .testTarget(name: "QueenBeeCoreTests", dependencies: ["QueenBeeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
