// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrollCaptureCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ScrollCaptureCore", targets: ["ScrollCaptureCore"]),
        .executable(name: "ScrollCaptureBenchmark", targets: ["ScrollCaptureBenchmark"])
    ],
    targets: [
        .target(name: "ScrollCaptureCore"),
        .executableTarget(name: "ScrollCaptureBenchmark", dependencies: ["ScrollCaptureCore"]),
        .testTarget(name: "ScrollCaptureCoreTests", dependencies: ["ScrollCaptureCore"])
    ]
)
