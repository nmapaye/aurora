import Foundation

/// SPIKE-1 (spike/apple-model-logging) only: the shared shapes and the
/// rule-based baseline for comparing typed-logging parsers on the fixed
/// phrase set in `AuroraTests/AppleModelSpike/phrases.json`. Not used by the
/// app. Times are whole minutes relative to the reference instant.
public enum LoggingEval {
    public struct Drink: Codable, Equatable, Sendable {
        public var source: String?
        public var mg: Double?
        public var atMin: Int?
        public init(source: String?, mg: Double?, atMin: Int?) { self.source = source; self.mg = mg; self.atMin = atMin }
    }

    public struct Sleep: Codable, Equatable, Sendable {
        public var startMin: Int?
        public var endMin: Int?
        public var durationMin: Int?
        public init(startMin: Int?, endMin: Int?, durationMin: Int?) { self.startMin = startMin; self.endMin = endMin; self.durationMin = durationMin }
    }

    /// `route` is "log" (a record would be drafted) or "none".
    public struct Parse: Codable, Equatable, Sendable {
        public var route: String
        public var drinks: [Drink]
        public var sleep: Sleep?
        public init(route: String, drinks: [Drink] = [], sleep: Sleep? = nil) { self.route = route; self.drinks = drinks; self.sleep = sleep }
        public static let none = Parse(route: "none")
    }

    public struct Case: Codable, Equatable, Sendable {
        public var id: String
        public var stratum: String
        public var phrase: String
        public var safety: Bool
        public var expect: Parse
    }

    public struct HistoryDrink: Codable, Equatable, Sendable {
        public var source: String
        public var mg: Double
        public var daysAgo: Int
    }

    public struct Reference: Codable, Equatable, Sendable {
        public var localTime: String
        public var timeZone: String
        public var history: [HistoryDrink]
    }

    public struct PhraseSet: Codable, Equatable, Sendable {
        public var version: Int
        public var reference: Reference
        public var cases: [Case]
    }

    public struct Latency: Codable, Equatable, Sendable {
        public var firstPartial: Double?
        public var total: Double
        public init(firstPartial: Double?, total: Double) { self.firstPartial = firstPartial; self.total = total }
    }

    /// One parser run on one phrase. `run` is "accuracy", "cold" or "warm".
    public struct Result: Codable, Equatable, Sendable {
        public var id: String
        public var parser: String
        public var run: String
        public var rep: Int
        /// After `sanitized`, what would reach a review card.
        public var output: Parse?
        /// Before `sanitized`; the invented-number check reads this.
        public var raw: Parse?
        public var latencyMs: Latency?
        public var error: String?
        public init(id: String, parser: String, run: String, rep: Int, raw: Parse?, latencyMs: Latency?, error: String? = nil) {
            self.id = id; self.parser = parser; self.run = run; self.rep = rep
            self.raw = raw; self.output = raw.map(LoggingEval.sanitized); self.latencyMs = latencyMs; self.error = error
        }
    }

    public struct ResultFile: Codable, Equatable, Sendable {
        public var meta: [String: String]
        public var results: [Result]
        public init(meta: [String: String], results: [Result]) { self.meta = meta; self.results = results }
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder
    }
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }

    public static func clock(_ reference: Reference) -> LocalClock {
        LocalClock(timeZone: TimeZone(identifier: reference.timeZone) ?? .current)
    }

    /// "2026-10-08T10:00:00" in the reference zone.
    public static func now(_ reference: Reference) -> Millis {
        let parts = reference.localTime.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        let clock = clock(reference)
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        components.hour = parts[3]; components.minute = parts[4]
        let date = clock.calendar.date(from: components)!
        return date.timeIntervalSince1970 * 1000
    }

    /// The usual-drink history both parsers see.
    public static func history(_ reference: Reference, now: Millis) -> [Dose] {
        reference.history.enumerated().map { index, drink in
            Dose(id: "history-\(index)", timestamp: now - Double(drink.daysAgo) * dayMs, mg: drink.mg, source: drink.source)
        }
    }

    public static func minutes(from now: Millis, to time: Millis) -> Int { Int(((time - now) / minuteMs).rounded()) }

    /// The deterministic checks every parser's output goes through before
    /// scoring, the same limits the app enforces on Save: amounts 1–1999 mg
    /// (`CaffeineLog.validate`), no future times, sleep between 1 minute and
    /// 24 hours ending by now. A log left with nothing becomes "none".
    public static func sanitized(_ parse: Parse) -> Parse {
        guard parse.route == "log" else { return .none }
        let drinks = parse.drinks.filter { drink in
            if let mg = drink.mg, !(mg >= 1 && mg <= 1999) { return false }
            if let at = drink.atMin, at > 0 { return false }
            return true
        }
        var sleep = parse.sleep
        if let s = sleep {
            let duration = s.durationMin ?? s.endMin.flatMap { end in s.startMin.map { end - $0 } }
            if let duration, !(duration >= 1 && duration <= 24 * 60) { sleep = nil }
            if let end = s.endMin, end > 0 { sleep = nil }
            if let start = s.startMin, let end = s.endMin, end <= start { sleep = nil }
        }
        if drinks.isEmpty && sleep == nil { return .none }
        return Parse(route: "log", drinks: drinks, sleep: sleep)
    }

    /// The existing deterministic path, unchanged: `AssistantPlanner.explicitIntent`
    /// (Assistant.swift:68) routes; a caffeine log is drafted by
    /// `AssistantPlanner.caffeineDraft` (Assistant.swift:181, with
    /// `mentionedTime` at :197 and `usual` at :157). A sleep log opens an
    /// empty review card (AssistantModel.swift:306–312, no usual night in the
    /// history), so its times are nil. Anything else, including requests the
    /// app would send to the model classifier, is "none".
    public static func ruleBased(_ phrase: String, history: [Dose], now: Millis, clock: LocalClock) -> Parse {
        switch AssistantPlanner.explicitIntent(phrase) {
        case .logCaffeine:
            let draft = AssistantPlanner.caffeineDraft(phrase, doses: history, now: now, clock: clock)
            let source = draft.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let drink = Drink(source: source.isEmpty ? nil : source, mg: Double(draft.mg), atMin: minutes(from: now, to: draft.timestamp))
            return Parse(route: "log", drinks: [drink])
        case .logSleep:
            let usual = AssistantPlanner.usualNight([], now: now, clock: clock)
            return Parse(route: "log", sleep: Sleep(
                startMin: usual.map { minutes(from: now, to: $0.start) }, endMin: usual.map { minutes(from: now, to: $0.end) }, durationMin: nil))
        default:
            return .none
        }
    }
}
