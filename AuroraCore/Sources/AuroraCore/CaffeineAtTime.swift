import Foundation

/// Caffeine follow-up chat, slice 1 core: "how much caffeine is active at
/// <time>", optionally with a drink that is asked about but never logged.
///
/// Every number is `Caffeine.activeMg` on absolute instants. Aurora picks no
/// threshold, rating, bedtime or amount; nothing here writes records. Unlike
/// `CutoffScenario` (whose past-drink guard is unchanged), the unlogged drink
/// may be at any time, including the past, because it is evaluated only.
public enum CaffeineAtTime {
    public static let modelVersion = "caffeine-at-time-1"

    // MARK: Copy (code-written; no generated text on this card)

    public static let title = "Estimated Active Caffeine"
    public static let notLoggedLabel = "Not Logged"
    public static let noRecordText = "No record"
    public static let logThisDrinkLabel = "Log This Drink"
    /// Source for the range in `halfLifeInfo`: 2.7–9.9 h across healthy
    /// adults (docs/research/caffeine.md, Established).
    public static let halfLifeRangeSource = "Blanchard & Sawers 1983"

    /// The text behind the card's (i), with the person's own setting.
    public static func halfLifeInfo(_ halfLifeHours: Double) -> String {
        "Estimated with your half-life setting (\(numberText(halfLifeHours)) h). Studies of healthy adults report half-lives from about 3 to 10 hours."
    }

    /// Card rounding: nearest 5 mg, halves away from zero (62.5 → 65), shown
    /// as "About N mg". The golden case 67.1 / 58.4 / 50.8 / 44.2 gives
    /// 65 / 60 / 50 / 45. Recorded totals elsewhere stay whole mg.
    public static func displayMg(_ mg: Double) -> Int {
        Int((mg / 5).rounded(.toNearestOrAwayFromZero) * 5)
    }

    // MARK: Input

    /// Where an asked-about drink's mg came from, so a correction knows
    /// whether to keep the amount (typed) or re-resolve it (database).
    public enum Provenance: Codable, Equatable, Hashable, Sendable {
        case typed
        case database(entryID: String, serving: String)
    }

    /// A drink in a question. Never saved; "Log This Drink" opens the
    /// existing confirm card instead.
    public struct UnloggedDrink: Codable, Equatable, Sendable {
        public var mg: Double
        public var at: Millis
        public var provenance: Provenance
        public init(mg: Double, at: Millis, provenance: Provenance) { self.mg = mg; self.at = at; self.provenance = provenance }
        public var label: String { CaffeineAtTime.notLoggedLabel }
    }

    public enum Problem: String, Codable, CaseIterable, Sendable {
        case invalidHalfLife, invalidAmount, missingTime
    }

    // MARK: Result

    public struct Row: Codable, Equatable, Sendable {
        public var at: Millis
        public var recordedMg: Double
        public var sampleMg: Double
        public var unloggedMg: Double
        /// Doses at or before `at` (recorded, sample and the unlogged drink).
        public var contributing: Int
        public var includesSample: Bool
        public var totalMg: Double { recordedMg + sampleMg + unloggedMg }
        /// Nothing recorded or stated by this time: "No record", never 0 mg.
        public var isNoRecord: Bool { contributing == 0 }
        public var displayMg: Int? { isNoRecord ? nil : CaffeineAtTime.displayMg(totalMg) }
        public var valueText: String { displayMg.map { "About \($0) mg" } ?? CaffeineAtTime.noRecordText }
    }

    public struct Result: Codable, Equatable, Sendable {
        public var problems: [Problem]
        public var rows: [Row]
        public var halfLifeHours: Double
        public var unlogged: UnloggedDrink?
        /// Known (at or before now) entries used.
        public var recordedCount: Int
        public var sampleCount: Int
        /// Entries dated after now: never used, only counted.
        public var excludedFutureCount: Int
        /// Every known entry used, as `id|time|mg`, like `CutoffScenario`.
        public var basis: [String]
        public var includesSample: Bool { rows.contains { $0.includesSample } }
    }

    // MARK: Evaluation

    /// Pure: reads `doses`, returns numbers, writes nothing. Targets are
    /// instants; resolve wall-clock times with `CutoffScenario.resolve` so
    /// repeated and skipped DST times are asked, not guessed.
    public static func evaluate(doses: [Dose], unlogged: UnloggedDrink?, halfLifeHours: Double, targets: [Millis], now: Millis) -> Result {
        var problems: [Problem] = []
        if !(halfLifeHours.isFinite && halfLifeHours > 0) { problems.append(.invalidHalfLife) }
        if let unlogged, !(unlogged.mg.isFinite && unlogged.mg > 0 && unlogged.at.isFinite) { problems.append(.invalidAmount) }
        if targets.isEmpty { problems.append(.missingTime) }

        let known = doses.filter { $0.timestamp <= now }
        let recorded = known.filter { !RecordID.isSample($0.id) }
        let sample = known.filter { RecordID.isSample($0.id) }
        let basis = known.map { "\($0.id)|\(Int64($0.timestamp))|\($0.mg)" }.sorted()

        var rows: [Row] = []
        if problems.isEmpty {
            let asked = unlogged.map { [Dose(id: "unlogged", timestamp: $0.at, mg: $0.mg)] } ?? []
            rows = targets.map { t in
                let sampleUsed = sample.filter { $0.timestamp <= t }.count
                return Row(
                    at: t,
                    recordedMg: Caffeine.activeMg(at: t, doses: recorded, halfLifeHours: halfLifeHours),
                    sampleMg: Caffeine.activeMg(at: t, doses: sample, halfLifeHours: halfLifeHours),
                    unloggedMg: Caffeine.activeMg(at: t, doses: asked, halfLifeHours: halfLifeHours),
                    contributing: recorded.filter { $0.timestamp <= t }.count + sampleUsed + asked.filter { $0.timestamp <= t }.count,
                    includesSample: sampleUsed > 0
                )
            }
        }
        return Result(problems: problems, rows: rows, halfLifeHours: halfLifeHours, unlogged: unlogged,
                      recordedCount: recorded.count, sampleCount: sample.count,
                      excludedFutureCount: doses.count - known.count, basis: basis)
    }

    // MARK: Sleep-time chip

    /// "Recent Sleep Start · 11:05 PM · 7 Nights": offered as a chip, used
    /// only when tapped. Nil means the card asks with a time picker.
    public struct SleepTimeChip: Codable, Equatable, Sendable {
        public var minuteOfDay: Int
        public var nights: Int
        public init(minuteOfDay: Int, nights: Int) { self.minuteOfDay = minuteOfDay; self.nights = nights }

        public func label(clockTime: String) -> String {
            "Recent Sleep Start · \(clockTime) · \(nights) \(nights == 1 ? "Night" : "Nights")"
        }

        /// The next instant at this wall time after `now`.
        public func nextStart(after now: Millis, clock: LocalClock) -> Millis {
            let today = clock.setTime(now, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
            return today > now ? today : clock.setTime(clock.addingDays(1, to: clock.startOfDay(now)), hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        }
    }

    public static let sleepChipMinimumNights = 3
    public static let sleepChipWindowDays = 14

    /// Median sleep start of recorded nights (manual and Health, not Sample
    /// Data): main sleeps of 3–16 h that ended in the last 14 days, one per
    /// wake-up day (manual preferred, then the longest). Needs at least 3.
    /// The median is taken on a noon-shifted clock, so 23:30, 00:15 and
    /// 00:45 give 00:15. Never uses `Prefs.targetSleep`: it takes sessions only.
    public static func recentSleepStart(_ sessions: [SleepSession], now: Millis, clock: LocalClock) -> SleepTimeChip? {
        let candidates = sessions.filter {
            $0.type == .sleep && !RecordID.isSample($0.id) && $0.end <= now && $0.end >= now - Millis(sleepChipWindowDays) * dayMs &&
            $0.end - $0.start >= 3 * hourMs && $0.end - $0.start <= 16 * hourMs
        }
        let nights = Dictionary(grouping: candidates) { clock.dayKey($0.end) }.values.compactMap { group in
            group.max { a, b in
                let am = RecordID.isManualSleep(a.id), bm = RecordID.isManualSleep(b.id)
                if am != bm { return !am }
                return a.end - a.start < b.end - b.start
            }
        }
        guard nights.count >= sleepChipMinimumNights else { return nil }
        let minutes = nights.map { night -> Double in
            let parts = clock.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: night.start / 1000))
            return Double(((parts.hour ?? 0) * 60 + (parts.minute ?? 0) + 720) % 1440)
        }.sorted()
        let middle = minutes.count / 2
        let median = minutes.count.isMultiple(of: 2) ? (minutes[middle - 1] + minutes[middle]) / 2 : minutes[middle]
        return SleepTimeChip(minuteOfDay: (Int(median) + 720) % 1440, nights: nights.count)
    }
}

/// Deterministic route for follow-up questions, so they work with Apple
/// Intelligence off (no model call). Only "how much caffeine is active /
/// will I have at <time>" and "<n> mg … at <time>?" questions qualify;
/// anything asking for an amount to drink stays `.unsupported`. Times are
/// parsed, never guessed: a bare hour or "into 5pm" becomes chips.
public enum CaffeineQuestion {
    public enum TimeSpec: Codable, Equatable, Hashable, Sendable {
        case now
        /// A fully specified wall time (am/pm, 24-hour, noon, midnight).
        case clock(hour: Int, minute: Int)
        /// 1–12 with no am/pm ("at 11", "5:27"): ask AM or PM.
        case ambiguousHour(hour: Int, minute: Int)
        /// "into 5pm" for a drink: ask "At 5:00 PM" or "Now".
        case into(hour: Int, minute: Int)
        /// "bedtime", "tonight": the sleep-time chip or picker.
        case sleepTime
    }

    public struct Parsed: Codable, Equatable, Sendable {
        /// Typed by the person; provenance `.typed`.
        public var drinkMg: Double?
        /// A drink or amount is part of the question (mg may still be missing).
        public var drinkMentioned: Bool
        public var drinkTime: TimeSpec?
        /// -1 for "yesterday".
        public var drinkDayOffset: Int
        /// Empty means the card offers its default times.
        public var targets: [TimeSpec]
        public init(drinkMg: Double?, drinkMentioned: Bool, drinkTime: TimeSpec?, drinkDayOffset: Int, targets: [TimeSpec]) {
            self.drinkMg = drinkMg; self.drinkMentioned = drinkMentioned; self.drinkTime = drinkTime
            self.drinkDayOffset = drinkDayOffset; self.targets = targets
        }
    }

    public enum Route: Codable, Equatable, Sendable {
        case caffeineAt(Parsed)
        /// Asking what or how much to drink: never answered.
        case unsupported
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    static let advicePattern = #"\b(should|can i|could i|may i|allowed|safe|ok(ay)? to|recommend\w*|how much more|to drink|max(imum)?|limit|too much)\b"#
    static let howMuchNext = #"how much\s+(caffeine|mg|will|is|would|do|does|i'll|ill|i|there|active|of|at|by|in|left|tonight)\b"#
    static let pastTense = #"\b(did|was|were)\b"#
    static let loggingVerb = #"\b(i had|i drank|i've had|ive had|i just had|log|add|record|save)\b"#
    static let questionMarker = #"(\?|\b(impact|mean|means|effect|affect|difference|what about|what if|tonight|bedtime)\b)"#
    static let drinkWord = #"\b(coffee|caffeine|espresso|tea|matcha|cold brew|energy drink|latte|soda|drink|cup|shot)\b"#

    public static func route(_ input: String) -> Route? {
        let text = input.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        let howMuch = text.range(of: "how much")
        let mg = singleMg(text)
        if (howMuch != nil || text.contains("recommend") || mg != nil) && matches(advicePattern, text) { return .unsupported }

        if let howMuch {
            guard matches(howMuchNext, text) else { return nil }
            let ifRange = text.range(of: #"\bif\b"#, options: .regularExpression)
            let drinkClause: Substring, targetClause: Substring
            if let ifRange, ifRange.lowerBound > howMuch.lowerBound {
                drinkClause = text[ifRange.lowerBound...]; targetClause = text[howMuch.upperBound..<ifRange.lowerBound]
            } else if let ifRange {
                drinkClause = text[ifRange.lowerBound..<howMuch.lowerBound]; targetClause = text[howMuch.upperBound...]
            } else {
                drinkClause = text[..<howMuch.lowerBound]; targetClause = text[howMuch.upperBound...]
            }
            if matches(pastTense, String(targetClause)) { return nil }
            let targets = times(in: String(targetClause), forDrink: false)
            guard !targets.isEmpty else { return nil }
            let drink = String(drinkClause)
            let drinkMg = singleMg(drink)
            return .caffeineAt(Parsed(drinkMg: drinkMg, drinkMentioned: drinkMg != nil || matches(drinkWord, drink),
                                      drinkTime: times(in: drink, forDrink: true).first, drinkDayOffset: drink.contains("yesterday") ? -1 : 0,
                                      targets: targets))
        }

        // "<n> mg … at <time>?" without "how much".
        guard let mg, matches(questionMarker, text), !matches(loggingVerb, text) || matches(#"\bif\b"#, text) else { return nil }
        var found = times(in: text, forDrink: true)
        guard !found.isEmpty else { return nil }
        var drinkTime: TimeSpec?
        if found[0] != .sleepTime { drinkTime = found.removeFirst() }
        let targets = found.map { spec -> TimeSpec in
            if case .into(let h, let m) = spec { return .clock(hour: h, minute: m) }
            return spec
        }
        return .caffeineAt(Parsed(drinkMg: mg, drinkMentioned: true, drinkTime: drinkTime, drinkDayOffset: text.contains("yesterday") ? -1 : 0, targets: targets))
    }

    /// Exactly one "<n> mg" amount, as `caffeineDraft` reads it; two or more give nil.
    static func singleMg(_ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d.])(\d+(?:\.\d+)?)\s*mg\b"#) else { return nil }
        let found = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard found.count == 1, let range = Range(found[0].range(at: 1), in: text), let value = Double(text[range]), value > 0 else { return nil }
        return value
    }

    static let timePattern = #"(?:\b(?<prep>at|by|around|into|until|till|for)\s+)?(?:\b(?<h12>1[0-2]|0?[1-9])(?::(?<m12>[0-5]\d))?\s*(?<ap>[ap])\.?m\b\.?|\b(?<h24>[01]?\d|2[0-3]):(?<m24>[0-5]\d)\b|\b(?<noon>noon|midday)\b|\b(?<mid>midnight)\b|\b(?<now>right now|now)\b|\b(?<sleep>bed ?time|tonight|when i (?:go to )?(?:sleep|bed)|before bed|i go to bed|i fall asleep)\b|\b(?<bare>1[0-2]|0?[1-9])\b(?!\s*(?:mg|oz|ml|hours?|hrs?|h\b|min|minutes?|cups?|shots?|cans?|:|[ap]\.?m\b|/|out of)))"#

    /// Time mentions in order. In a drink clause, "into 5pm" stays `.into`.
    static func times(in text: String, forDrink: Bool) -> [TimeSpec] {
        guard let regex = try? NSRegularExpression(pattern: timePattern) else { return [] }
        func group(_ match: NSTextCheckingResult, _ name: String) -> String? {
            Range(match.range(withName: name), in: text).map { String(text[$0]) }
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> TimeSpec? in
            let prep = group(match, "prep")
            var spec: TimeSpec
            if let h = group(match, "h12").flatMap(Int.init), let ap = group(match, "ap") {
                spec = .clock(hour: h % 12 + (ap == "p" ? 12 : 0), minute: group(match, "m12").flatMap(Int.init) ?? 0)
            } else if let h = group(match, "h24").flatMap(Int.init), let m = group(match, "m24").flatMap(Int.init) {
                spec = (h == 0 || h >= 13) ? .clock(hour: h, minute: m) : .ambiguousHour(hour: h, minute: m)
            } else if group(match, "noon") != nil { spec = .clock(hour: 12, minute: 0)
            } else if group(match, "mid") != nil { spec = .clock(hour: 0, minute: 0)
            } else if group(match, "now") != nil { spec = .now
            } else if group(match, "sleep") != nil { spec = .sleepTime
            } else if let h = group(match, "bare").flatMap(Int.init), prep != nil { spec = .ambiguousHour(hour: h, minute: 0)
            } else { return nil }
            if forDrink, prep == "into", case .clock(let h, let m) = spec { spec = .into(hour: h, minute: m) }
            return spec
        }
    }

    /// The chips a time needs before it can be used; empty when it's usable
    /// as is (or, for `.sleepTime`, when the sleep chip or picker applies).
    public static func choices(for spec: TimeSpec) -> [TimeSpec] {
        switch spec {
        case .ambiguousHour(let h, let m): [.clock(hour: h % 12, minute: m), .clock(hour: h % 12 + 12, minute: m)]
        case .into(let h, let m): [.clock(hour: h, minute: m), .now]
        case .now, .clock, .sleepTime: []
        }
    }

    /// A queried time: its first occurrence after `anchor` (the drink time,
    /// else now). Resolve the result with `CutoffScenario.resolve`.
    public static func targetLocalTime(hour: Int, minute: Int, after anchor: Millis, timeZone: TimeZone) -> CutoffScenario.LocalTime {
        let base = CutoffScenario.LocalTime(anchor, timeZone: timeZone)
        let later = hour * 60 + minute > base.hour * 60 + base.minute
        return shifted(base, days: later ? 0 : 1, hour: hour, minute: minute)
    }

    /// A drink time: today, or yesterday with `dayOffset` -1. Past times are allowed.
    public static func drinkLocalTime(hour: Int, minute: Int, dayOffset: Int, now: Millis, timeZone: TimeZone) -> CutoffScenario.LocalTime {
        shifted(CutoffScenario.LocalTime(now, timeZone: timeZone), days: dayOffset, hour: hour, minute: minute)
    }

    private static func shifted(_ base: CutoffScenario.LocalTime, days: Int, hour: Int, minute: Int) -> CutoffScenario.LocalTime {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: base.year, month: base.month, day: base.day + days, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return .init(year: parts.year ?? base.year, month: parts.month ?? base.month, day: parts.day ?? base.day, hour: hour, minute: minute)
    }
}
