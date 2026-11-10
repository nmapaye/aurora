// swift-tools-version: 6.0
import PackageDescription

/// Research-only, unvalidated Three-Process Model KSS formula
/// (Sources/AuroraCore/Research). Compiled into Debug builds only, so Release
/// and TestFlight builds do not contain it. Nothing in the app references it.
let researchKSS: [SwiftSetting] = [.define("AURORA_RESEARCH_KSS", .when(configuration: .debug))]

let package = Package(
    name: "AuroraCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AuroraCore", targets: ["AuroraCore"]),
    ],
    targets: [
        .target(
            name: "AuroraCore",
            exclude: ["Research/CITATIONS.md"],
            swiftSettings: researchKSS
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: researchKSS
        ),
    ]
)
