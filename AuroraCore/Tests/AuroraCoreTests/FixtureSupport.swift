import Foundation
import Testing
@testable import AuroraCore

/// Loads the JSON files that `tests/fixtures/exportCoreFixtures.spec.ts`
/// wrote from the TypeScript originals.
enum Fixture {
    static func load(_ name: String) throws -> JSONValue {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONValue(parsing: Data(contentsOf: url))
    }

    static let zones = ["UTC", "America_Los_Angeles"]
}

/// The deterministic formatters the fixtures used: `T<ms>` and `D<ms>`.
let fixtureText = DateText(
    clockTime: { "T\(numberText($0))" },
    shortDate: { "S\(numberText($0))" },
    weekdayDate: { "D\(numberText($0))" },
    fullDateTime: { "F\(numberText($0))" }
)

func fixtureTime(_ ms: Millis) -> String { "T\(numberText(ms))" }

extension JSONValue {
    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var isNull: Bool { self == .null }

    func double(_ key: String) -> Double? { self[key]?.number }
    func int(_ key: String) -> Int? { self[key]?.number.map { Int($0) } }
    func text(_ key: String) -> String? { self[key]?.string }
    func flag(_ key: String) -> Bool? { self[key]?.bool }
    func list(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
}

func dose(_ value: JSONValue) -> Dose {
    Dose(
        id: value.text("id") ?? "",
        timestamp: value.double("timestamp") ?? .nan,
        mg: value.double("mg") ?? .nan,
        source: value.text("source"),
        note: value.text("note")
    )
}

func sleepSession(_ value: JSONValue) -> SleepSession {
    SleepSession(
        id: value.text("id") ?? "",
        start: value.double("start") ?? .nan,
        end: value.double("end") ?? .nan,
        type: SleepType(rawValue: value.text("type") ?? "sleep") ?? .sleep,
        note: value.text("note")
    )
}

func vigilance(_ value: JSONValue) -> VigilanceSession {
    VigilanceSession(
        id: value.text("id") ?? "",
        startedAt: value.double("startedAt") ?? 0,
        completedAt: value.double("completedAt") ?? 0,
        durationMs: value.double("durationMs") ?? 0,
        trialCount: value.int("trialCount") ?? 0,
        validReactionCount: value.int("validReactionCount") ?? 0,
        falseStartCount: value.int("falseStartCount") ?? 0,
        lapseCount: value.int("lapseCount") ?? 0,
        medianReactionMs: value.double("medianReactionMs"),
        meanReactionMs: value.double("meanReactionMs"),
        fastestReactionMs: value.double("fastestReactionMs"),
        reactionStdDevMs: value.double("reactionStdDevMs"),
        score: value.int("score") ?? 0,
        rating: VigilanceRating(rawValue: value.text("rating") ?? "") ?? .sluggish
    )
}

/// Compares a Swift signal with the fixture's object. Keys the fixture
/// dropped (set to `undefined` there) are skipped.
func expectSignal(_ signal: SignalCardModel, _ expected: JSONValue, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(signal.id == expected.text("id"), sourceLocation: sourceLocation)
    #expect(signal.label == expected.text("label"), sourceLocation: sourceLocation)
    #expect(signal.status.rawValue == expected.text("status"), sourceLocation: sourceLocation)
    #expect(signal.source == expected.text("source"), sourceLocation: sourceLocation)
    #expect(signal.value == expected.text("value"), sourceLocation: sourceLocation)
    #expect(signal.context == expected.text("context"), sourceLocation: sourceLocation)
    #expect(signal.destination == expected.text("destination"), sourceLocation: sourceLocation)
    if let period = expected.text("period") {
        #expect(signal.period == period, sourceLocation: sourceLocation)
    }
}

func approxEqual(_ lhs: Double?, _ rhs: Double?, tolerance: Double = 1e-6) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case let (l?, r?): return abs(l - r) <= tolerance * max(1, abs(r))
    default: return false
    }
}
