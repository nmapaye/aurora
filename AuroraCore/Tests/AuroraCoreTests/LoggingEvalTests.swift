#if DEBUG
import Foundation
import Testing
@testable import AuroraCore

/// SPIKE-1: runs the rule-based baseline over the fixed phrase set. Set
/// AURORA_EVAL_OUT=/path/results-rule.json to write the results for
/// `spikes/apple-model-logging/score.py`.
struct LoggingEvalTests {
    static var phraseURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("AuroraTests/AppleModelSpike/phrases.json")
    }

    func load() throws -> LoggingEval.PhraseSet {
        try LoggingEval.decoder.decode(LoggingEval.PhraseSet.self, from: Data(contentsOf: Self.phraseURL))
    }

    @Test func phraseSetIsTheFixedThreeHundred() throws {
        let set = try load()
        #expect(set.cases.count == 300)
        #expect(Set(set.cases.map(\.id)).count == 300)
        #expect(set.cases.filter(\.safety).count == 40)
        // Gold records pass the same checks the parsers' output does.
        for item in set.cases { #expect(LoggingEval.sanitized(item.expect) == item.expect, "\(item.id)") }
    }

    @Test func referenceInstantIsTenAMLocal() throws {
        let reference = try load().reference
        let now = LoggingEval.now(reference)
        let clock = LoggingEval.clock(reference)
        #expect(clock.hour(now) == 10)
        #expect(LoggingEval.history(reference, now: now).count == 3)
    }

    @Test func sanitizedDropsWhatTheAppWouldRefuse() {
        let drink = { (mg: Double?, at: Int?) in LoggingEval.Drink(source: "Coffee", mg: mg, atMin: at) }
        #expect(LoggingEval.sanitized(.init(route: "log", drinks: [drink(5000, 0)])) == .none)
        #expect(LoggingEval.sanitized(.init(route: "log", drinks: [drink(0, 0)])) == .none)
        #expect(LoggingEval.sanitized(.init(route: "log", drinks: [drink(95, 60)])) == .none)
        #expect(LoggingEval.sanitized(.init(route: "log", drinks: [drink(nil, 0)])).drinks.count == 1)
        #expect(LoggingEval.sanitized(.init(route: "log", sleep: .init(startMin: nil, endMin: nil, durationMin: 26 * 60))) == .none)
        #expect(LoggingEval.sanitized(.init(route: "log", sleep: .init(startMin: -600, endMin: -600, durationMin: nil))) == .none)
    }

    @Test func ruleBasedBaselineMatchesTheAppPath() throws {
        let set = try load()
        let now = LoggingEval.now(set.reference)
        let clock = LoggingEval.clock(set.reference)
        let history = LoggingEval.history(set.reference, now: now)
        let parse = { LoggingEval.sanitized(LoggingEval.ruleBased($0, history: history, now: now, clock: clock)) }
        #expect(parse("I had a 150 mg coffee") == .init(route: "log", drinks: [.init(source: "Coffee", mg: 150, atMin: 0)]))
        #expect(parse("I had my usual") == .init(route: "log", drinks: [.init(source: "Cold Brew", mg: 200, atMin: 0)]))
        #expect(parse("I had an espresso yesterday at 8am") == .init(route: "log", drinks: [.init(source: "Espresso", mg: nil, atMin: -1560)]))
        #expect(parse("how much caffeine should I have") == .none)
        #expect(parse("I didn't have coffee today") == .none)

        var results: [LoggingEval.Result] = []
        for item in set.cases {
            let start = DispatchTime.now().uptimeNanoseconds
            let raw = LoggingEval.ruleBased(item.phrase, history: history, now: now, clock: clock)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            results.append(.init(id: item.id, parser: "rule", run: "accuracy", rep: 0, raw: raw, latencyMs: .init(firstPartial: nil, total: ms)))
        }
        #expect(results.count == 300)
        if let path = ProcessInfo.processInfo.environment["AURORA_EVAL_OUT"] {
            let file = LoggingEval.ResultFile(meta: ["parser": "rule", "platform": "linux", "phrases_version": "\(set.version)"], results: results)
            try LoggingEval.encoder.encode(file).write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
