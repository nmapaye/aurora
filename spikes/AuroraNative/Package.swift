// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuroraNativeSpike",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AuroraSpikeCore", targets: ["AuroraSpikeCore"]),
        .library(name: "AuroraSpikeUI", targets: ["AuroraSpikeUI"]),
        .executable(name: "AuroraSpikePreview", targets: ["AuroraSpikePreview"]),
    ],
    targets: [
        .target(name: "AuroraSpikeCore"),
        .target(name: "AuroraSpikeUI", dependencies: ["AuroraSpikeCore"]),
        .executableTarget(name: "AuroraSpikePreview", dependencies: ["AuroraSpikeUI"]),
        .testTarget(name: "AuroraSpikeCoreTests", dependencies: ["AuroraSpikeCore"]),
    ]
)
