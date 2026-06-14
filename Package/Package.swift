// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemPush",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RemPushCore", targets: ["RemPushCore"]),
    ],
    targets: [
        .target(name: "RemPushCore"),
        .testTarget(name: "RemPushCoreTests", dependencies: ["RemPushCore"])
    ]
)
