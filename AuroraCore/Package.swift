// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuroraCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AuroraCore", targets: ["AuroraCore"]),
    ],
    targets: [
        .target(name: "AuroraCore"),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
