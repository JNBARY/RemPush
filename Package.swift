// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemPush",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RemPushCore", targets: ["RemPushCore"]),
        .library(name: "RemPushApp", targets: ["RemPushApp"])
    ],
    targets: [
        .target(name: "RemPushCore"),
        .target(name: "RemPushApp", dependencies: ["RemPushCore"]),
        .testTarget(name: "RemPushCoreTests", dependencies: ["RemPushCore"])
    ]
)
