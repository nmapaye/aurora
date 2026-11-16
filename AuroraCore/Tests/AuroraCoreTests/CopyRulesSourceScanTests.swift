import Foundation
import Testing
@testable import AuroraCore

/// CopyRules over every string literal in the app target and AuroraCore's
/// sources, not just the onboarding and welcome lines: no "remaining
/// caffeine", "safe amount", "you should…" and the rest anywhere a person
/// could read it. Excluded: the research models and their flagged Debug
/// screen (off by default, never shown to normal users) and CopyRules' own
/// pattern. Comments are skipped.
@Suite struct CopyRulesSourceScanTests {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let excluded: Set<String> = ["ResearchModelsView.swift", "Onboarding+Copy.swift"]

    /// Ordinary and multi-line string literals, skipping `//` comments and
    /// raw `#"…"#` literals (regex patterns).
    static func literals(in source: String) -> [String] {
        var found: [String] = []
        var block: [String]?
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var lines = block {
                if trimmed.hasPrefix("\"\"\"") { found.append(lines.joined(separator: "\n")); block = nil } else { lines.append(line); block = lines }
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            if trimmed.hasSuffix("\"\"\"") && !trimmed.hasPrefix("\"\"\"") || trimmed == "\"\"\"" { block = []; continue }
            var inside = false, escaped = false, current = "", previous: Character = " ", raw = false
            for character in line {
                if inside {
                    if escaped { escaped = false; current.append(character) }
                    else if character == "\\" { escaped = true; current.append(character) }
                    else if character == "\"" { inside = false; if !raw { found.append(current) }; current = "" }
                    else { current.append(character) }
                } else if character == "\"" { inside = true; raw = previous == "#" }
                else if character == "/" && previous == "/" { break }
                previous = character
            }
        }
        return found
    }

    @Test func scannerFindsLiteralsAndSkipsCommentsAndPatterns() {
        let source = """
        let a = "Caffeine remaining caffeine"
        // "you should sleep" in a comment
        let b = #"\\b(safe amount)\\b"#
        """
        #expect(Self.literals(in: source) == ["Caffeine remaining caffeine"])
        #expect(!CopyRules.violations(in: Self.literals(in: source)[0]).isEmpty)
    }

    @Test func noUserFacingStringInTheAppOrCoreBreaksCopyRules() throws {
        let app = Self.repo.appendingPathComponent("Aurora")
        // The app sources sit beside the package in the repo checkout.
        try #require(FileManager.default.fileExists(atPath: app.path))
        var scanned = 0
        for dir in [app, Self.repo.appendingPathComponent("AuroraCore/Sources/AuroraCore")] {
            let walker = try #require(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil))
            for case let url as URL in walker where url.pathExtension == "swift" {
                if Self.excluded.contains(url.lastPathComponent) || url.pathComponents.contains("Research") { continue }
                for literal in Self.literals(in: try String(contentsOf: url, encoding: .utf8)) {
                    #expect(CopyRules.violations(in: literal).isEmpty, "\(url.lastPathComponent): \(literal)")
                }
                scanned += 1
            }
        }
        #expect(scanned > 100)
    }
}
