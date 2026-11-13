// swift-tools-version: 6.0
import PackageDescription

/// Research-only, unvalidated models (Sources/AuroraCore/Research), compiled
/// into Debug builds only, so Release and TestFlight builds contain neither:
/// - AURORA_RESEARCH_KSS: the Three-Process Model KSS formula (#89).
/// - AURORA_RESEARCH_CAFFEINE: the Unified Model of Performance with its
///   caffeine factor (#90). Debug-only like KSS so the Debug Research screen
///   can show both side by side; it was test-flag-only before.
/// The only app code that references them is the `#if DEBUG` Research screen.
let research: [SwiftSetting] = [
    .define("AURORA_RESEARCH_KSS", .when(configuration: .debug)),
    .define("AURORA_RESEARCH_CAFFEINE", .when(configuration: .debug)),
]

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
            resources: [.copy("Resources/caffeine-db.json")],
            swiftSettings: research
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: research
        ),
    ]
)
