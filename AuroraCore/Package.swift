// swift-tools-version: 6.0
import PackageDescription

/// Research-only, unvalidated models (Sources/AuroraCore/Research) are off by
/// default in Debug and Release. They compile only when a build passes the
/// flags explicitly, e.g.
///   swift test -Xswiftc -DAURORA_RESEARCH_KSS -Xswiftc -DAURORA_RESEARCH_CAFFEINE
/// - AURORA_RESEARCH_KSS: the Three-Process Model KSS formula (#89).
/// - AURORA_RESEARCH_CAFFEINE: the Unified Model of Performance with its
///   caffeine factor (#90).
/// The only app code that references them is the Debug Research screen, which
/// also needs both flags. `ResearchFlagsTests` fails if a define comes back.

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
            resources: [.copy("Resources/caffeine-db.json")]
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
