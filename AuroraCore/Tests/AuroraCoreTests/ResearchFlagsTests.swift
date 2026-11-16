import Foundation
import Testing
@testable import AuroraCore

/// Research-only models (Three-Process Model KSS, UMP with caffeine) are off
/// by default in Debug and Release. They compile only when a build passes
/// -DAURORA_RESEARCH_KSS / -DAURORA_RESEARCH_CAFFEINE explicitly.
@Suite struct ResearchFlagsTests {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func packageDefinesNoResearchFlagInAnyConfiguration() throws {
        let manifest = try String(contentsOf: Self.repo.appendingPathComponent("AuroraCore/Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".define(\"AURORA_RESEARCH_KSS\""))
        #expect(!manifest.contains(".define(\"AURORA_RESEARCH_CAFFEINE\""))
    }

    @Test func appResearchScreenNeedsBothExplicitFlags() throws {
        let screen = try String(contentsOf: Self.repo.appendingPathComponent("Aurora/Screens/Debug/ResearchModelsView.swift"), encoding: .utf8)
        #expect(screen.hasPrefix("#if DEBUG && AURORA_RESEARCH_KSS && AURORA_RESEARCH_CAFFEINE\n"))
        let settings = try String(contentsOf: Self.repo.appendingPathComponent("Aurora/Screens/Assistant/AssistantSettingsView.swift"), encoding: .utf8)
        let link = try #require(settings.range(of: "ResearchModelsView()"))
        let before = settings[..<link.lowerBound]
        let gate = try #require(before.range(of: "#if AURORA_RESEARCH_KSS && AURORA_RESEARCH_CAFFEINE", options: .backwards))
        #expect(!before[gate.upperBound...].contains("#endif"))
    }

    /// A plain `swift test` (Debug) or `-c release` run compiles no research
    /// model; a run that passes both flags sets AURORA_EXPECT_RESEARCH=1.
    @Test func compiledResearchMatchesTheFlagsPassed() {
        #if AURORA_RESEARCH_CAFFEINE
        let caffeine = true
        #else
        let caffeine = false
        #endif
        #if AURORA_RESEARCH_KSS
        let kss = true
        #else
        let kss = false
        #endif
        let expected = ProcessInfo.processInfo.environment["AURORA_EXPECT_RESEARCH"] == "1"
        #expect(caffeine == expected && kss == expected)
    }
}
