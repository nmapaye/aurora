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
    public static let loggedLabel = "Logged"
    /// A modeled value with records behind it that rounds below 5 mg.
    public static let lessThanFiveText = "Less than 5 mg"
    /// Source for the range in `halfLifeInfo`: Blanchard J, Sawers SJA. "The
    /// absolute bioavailability of caffeine in man." Eur J Clin Pharmacol
    /// 1983;24:93–98, doi:10.1007/BF00613933, PubMed 6832208: 10 healthy men
    /// aged 18.8–30, half-lives 2.7–9.9 h. Not the same authors' young vs
    /// elderly paper of the same year, which is not cited here.
    public static let halfLifeRangeSource = "Blanchard & Sawers 1983"
    public static let halfLifeRangeCitation = "Blanchard J, Sawers SJA. The absolute bioavailability of caffeine in man. Eur J Clin Pharmacol 1983;24:93–98. doi:10.1007/BF00613933. PubMed 6832208."

    /// The text behind the card's (i), with the person's own setting.
    public static func halfLifeInfo(_ halfLifeHours: Double) -> String {
        "Estimated with your half-life setting (\(numberText(halfLifeHours)) h). In one study of 10 healthy young men, half-lives ranged from about 3 to 10 hours."
    }

    /// Settings' (i) for Caffeine Half-Life: the card's text plus its source.
    public static func settingsHalfLifeInfo(_ halfLifeHours: Double) -> String {
        halfLifeInfo(halfLifeHours) + " Source: " + halfLifeRangeCitation
    }

    /// Card rounding: nearest 5 mg, halves away from zero (62.5 → 65), shown
    /// as "About N mg". The golden case 67.1 / 58.4 / 50.8 / 44.2 gives
    /// 65 / 60 / 50 / 45. Recorded totals elsewhere stay whole mg.
    /// Never traps: a non-finite value shows 0, and one beyond `Int`'s range
    /// is clamped (amounts the card accepts are 1–1999 mg, `CaffeineLog.isValidAmount`).
    public static func displayMg(_ mg: Double) -> Int {
        let rounded = (mg / 5).rounded(.toNearestOrAwayFromZero) * 5
        guard rounded.isFinite else { return 0 }
        return Int(min(max(rounded, -displayLimit), displayLimit))
    }
    static let displayLimit = 9_000_000_000_000_000_000.0

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
        /// Records contribute but the value rounds to 0: "Less than 5 mg",
        /// never "About 0 mg".
        public var isBelowDisplay: Bool { displayMg == 0 }
        public var valueText: String {
            guard let mg = displayMg else { return CaffeineAtTime.noRecordText }
            return mg == 0 ? CaffeineAtTime.lessThanFiveText : "About \(mg) mg"
        }
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
        /// "Not Logged" for an asked-about drink, "Logged" when the person
        /// chose the matching logged entry; nil with no drink in the question.
        public var drinkLabel: String?
        public var includesSample: Bool { rows.contains { $0.includesSample } }
    }

    // MARK: Asked drink vs a logged entry

    /// Never merged silently: two identical drinks 20 minutes apart are real.
    public static let duplicateWindowMs: Millis = 30 * minuteMs

    public enum DuplicateChoice: String, Codable, CaseIterable, Sendable {
        case useLogged, addAnother
        public var label: String {
            switch self {
            case .useLogged: "Use Logged Drink"
            case .addAnother: "Add as Another Drink"
            }
        }
    }

    /// The drink in a question, after any duplicate question is answered.
    public enum AskedDrink: Codable, Equatable, Sendable {
        /// The person chose an existing logged entry; it's already in the doses.
        case logged(doseID: String, mg: Double, at: Millis)
        case notLogged(UnloggedDrink)
        public var label: String {
            switch self {
            case .logged: CaffeineAtTime.loggedLabel
            case .notLogged: CaffeineAtTime.notLoggedLabel
            }
        }
        /// What the evaluator adds on top of the doses.
        public var unlogged: UnloggedDrink? {
            if case .notLogged(let drink) = self { return drink }
            return nil
        }
    }

    /// Two chips, no default: nothing is chosen until the person taps one.
    public struct DuplicateQuestion: Codable, Equatable, Sendable {
        public var drink: UnloggedDrink
        public var loggedDoseID: String
        public var loggedAt: Millis
        public var loggedMg: Double
        public var options: [DuplicateChoice] { DuplicateChoice.allCases }
        public func answer(_ choice: DuplicateChoice) -> AskedDrink {
            switch choice {
            case .useLogged: .logged(doseID: loggedDoseID, mg: loggedMg, at: loggedAt)
            case .addAnother: .notLogged(drink)
            }
        }
    }

    public enum AskedDrinkCheck: Codable, Equatable, Sendable {
        case resolved(AskedDrink)
        case needsChoice(DuplicateQuestion)
    }

    /// A past asked-about drink with a logged entry (not Sample Data, known
    /// at `now`) of the same mg within 30 minutes asks; anything else is
    /// added as "Not Logged" with no question. The closest entry is offered.
    public static func checkAskedDrink(_ drink: UnloggedDrink, doses: [Dose], now: Millis) -> AskedDrinkCheck {
        guard drink.at <= now else { return .resolved(.notLogged(drink)) }
        let match = doses
            .filter { !RecordID.isSample($0.id) && $0.timestamp <= now && $0.mg == drink.mg && abs($0.timestamp - drink.at) <= duplicateWindowMs }
            .min { abs($0.timestamp - drink.at) < abs($1.timestamp - drink.at) }
        guard let match else { return .resolved(.notLogged(drink)) }
        return .needsChoice(DuplicateQuestion(drink: drink, loggedDoseID: match.id, loggedAt: match.timestamp, loggedMg: match.mg))
    }

    /// Evaluates with an answered asked drink, labeled "Logged" or "Not Logged".
    public static func evaluate(doses: [Dose], asked: AskedDrink?, halfLifeHours: Double, targets: [Millis], now: Millis) -> Result {
        var result = evaluate(doses: doses, unlogged: asked?.unlogged, halfLifeHours: halfLifeHours, targets: targets, now: now)
        result.drinkLabel = asked?.label
        return result
    }

    // MARK: Evaluation

    /// Pure: reads `doses`, returns numbers, writes nothing. Targets are
    /// instants; resolve wall-clock times with `CutoffScenario.resolve` so
    /// repeated and skipped DST times are asked, not guessed.
    public static func evaluate(doses: [Dose], unlogged: UnloggedDrink?, halfLifeHours: Double, targets: [Millis], now: Millis) -> Result {
        var problems: [Problem] = []
        if !(halfLifeHours.isFinite && halfLifeHours > 0) { problems.append(.invalidHalfLife) }
        // The save contract (whole 1–1999 mg), so a question never takes an amount Save would refuse.
        if let unlogged, !(CaffeineLog.isValidAmount(unlogged.mg) && unlogged.at.isFinite) { problems.append(.invalidAmount) }
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
                      excludedFutureCount: doses.count - known.count, basis: basis,
                      drinkLabel: unlogged == nil ? nil : notLoggedLabel)
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

        /// This wall time's next occurrence after `now`, through the same
        /// resolver as every other time (`CaffeineQuestion.targetLocalTime`,
        /// `CutoffScenario.resolve`): a time clocks skip is `.skipped` and a
        /// time that happens twice is `.repeated`, for the person to choose.
        /// Never shifted, never a fold picked.
        public func nextStart(after now: Millis, timeZone: TimeZone) -> CutoffScenario.Resolution {
            let local = CaffeineQuestion.targetLocalTime(hour: minuteOfDay / 60, minute: minuteOfDay % 60, after: now, timeZone: timeZone)
            return CutoffScenario.resolve(local, in: timeZone)
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
        /// The day a clock target names; nil means its next occurrence.
        public var targetDay: TargetDay?
        public init(drinkMg: Double?, drinkMentioned: Bool, drinkTime: TimeSpec?, drinkDayOffset: Int, targets: [TimeSpec], targetDay: TargetDay? = nil) {
            self.drinkMg = drinkMg; self.drinkMentioned = drinkMentioned; self.drinkTime = drinkTime
            self.drinkDayOffset = drinkDayOffset; self.targets = targets; self.targetDay = targetDay
        }
    }

    /// The only days a queried time can name. Any other day asks again
    /// (`dayClarification`); a past day shows the capabilities list. A
    /// time is never moved to a different date.
    public enum TargetDay: String, Codable, Equatable, Sendable {
        case today, tomorrow
        /// Noon to midnight is today; after midnight is tomorrow.
        case tonight

        /// Days after the asked date for a target at `hour`.
        public func dayOffset(hour: Int) -> Int {
            switch self {
            case .today: 0
            case .tomorrow: 1
            case .tonight: hour >= 12 ? 0 : 1
            }
        }
    }

    public enum Route: Codable, Equatable, Sendable {
        case caffeineAt(Parsed)
        /// Asking what or how much to drink: never answered.
        case unsupported
        /// A past-tense question ("how much caffeine did I have at 3pm"):
        /// not answered in v0.1.0. The UI shows the standard capability
        /// chips (`fallbackCapabilities`, the "What can you do?" list), not a dead end.
        case showCapabilities
        /// A question with an amount the app can't use (outside whole
        /// 1–1999 mg): a plain line asking again, never a changed amount.
        case clarify(String)
    }

    public static let amountClarification = "Ask with a whole caffeine amount between 1 and 1999 mg."
    public static let dayClarification = "Ask about today or tomorrow, with a time."

    public static var fallbackCapabilities: [AssistantIntent] { Capabilities.all.map(\.intent) }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    static let advicePattern = #"\b(should|can i|could i|may i|allowed|safe|ok(ay)? to|recommend\w*|how much more|to drink|max(imum)?|limit|too much)\b"#
    static let howMuchNext = #"how much\s+(caffeine|mg|will|is|was|were|did|would|do|does|i'll|ill|i|there|active|of|at|by|in|left|tonight)\b"#
    static let pastTense = #"\b(did|was|were)\b"#
    static let loggingVerb = #"\b(i had|i drank|i've had|ive had|i just had|log|add|record|save)\b"#
    static let questionMarker = #"(\?|\b(impact|mean|means|effect|affect|difference|what about|what if|tonight|bedtime)\b)"#
    /// A past day in the queried time: not answered in v0.1.0.
    static let pastDay = #"\b(yesterday|last night|last week|ago)\b"#
    /// Days and dates the card doesn't place; checked before today/tomorrow.
    static let otherDay = #"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekend|next week|this week|day after|this morning|this afternoon|this evening|tomorrow (morning|afternoon|evening|night)|in \d+ days?|\d+ days? from now|(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept?|oct|nov|dec)\.? \d{1,2}|\d{1,2}(st|nd|rd|th)|\d{1,2}/\d{1,2})\b"#
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
            let target = String(targetClause), drink = String(drinkClause)
            if matches(pastTense, target) || matches(pastDay, target) { return .showCapabilities }
            if matches(otherDay, text) || matches(#"\b(tomorrow|last night|last week)\b"#, drink) { return .clarify(dayClarification) }
            var targets = times(in: target, forDrink: false)
            guard !targets.isEmpty else { return nil }
            let day: TargetDay?
            switch (target.contains("today"), target.contains("tomorrow"), matches(#"\btonight\b"#, target)) {
            case (false, false, false): day = nil
            case (true, false, false): day = .today
            case (false, true, false): day = .tomorrow
            case (false, false, true): day = .tonight
            default: return .clarify(dayClarification)
            }
            switch day {
            case .tomorrow?:
                // Bedtime and "now" are tonight's; only clock times move a day.
                if targets.contains(where: { $0 == .sleepTime || $0 == .now }) { return .clarify(dayClarification) }
            case .tonight?:
                // "at 11pm tonight": the time is the target, not the sleep chip.
                // "at bedtime tonight": one sleep time.
                if let i = targets.firstIndex(of: .sleepTime), targets.contains(where: { $0 != .sleepTime }) || targets.filter({ $0 == .sleepTime }).count > 1 { targets.remove(at: i) }
                var mapped: [TimeSpec] = []
                for spec in targets {
                    switch spec {
                    case .clock(let h, _) where (6..<12).contains(h): return .clarify(dayClarification)
                    case .ambiguousHour(12, let m): mapped.append(.clock(hour: 0, minute: m))
                    case .ambiguousHour(let h, let m) where h >= 6: mapped.append(.clock(hour: h + 12, minute: m))
                    default: mapped.append(spec)
                    }
                }
                targets = mapped
            default: break
            }
            let drinkMg = singleMg(drink)
            if let drinkMg, !CaffeineLog.isValidAmount(drinkMg) { return .clarify(amountClarification) }
            return .caffeineAt(Parsed(drinkMg: drinkMg, drinkMentioned: drinkMg != nil || matches(drinkWord, drink),
                                      drinkTime: times(in: drink, forDrink: true).first, drinkDayOffset: drink.contains("yesterday") ? -1 : 0,
                                      targets: targets, targetDay: targets.contains(where: { $0 != .sleepTime }) ? day : nil))
        }

        // "<n> mg … at <time>?" without "how much".
        guard let mg, matches(questionMarker, text), !matches(loggingVerb, text) || matches(#"\bif\b"#, text) else { return nil }
        // Without "how much" a day can't be tied to the drink or the target.
        if matches(otherDay, text) || matches(#"\b(tomorrow|last night|last week)\b"#, text) { return .clarify(dayClarification) }
        var found = times(in: text, forDrink: true)
        guard !found.isEmpty else { return nil }
        var drinkTime: TimeSpec?
        if found[0] != .sleepTime { drinkTime = found.removeFirst() }
        let targets = found.map { spec -> TimeSpec in
            if case .into(let h, let m) = spec { return .clock(hour: h, minute: m) }
            return spec
        }
        guard CaffeineLog.isValidAmount(mg) else { return .clarify(amountClarification) }
        return .caffeineAt(Parsed(drinkMg: mg, drinkMentioned: true, drinkTime: drinkTime, drinkDayOffset: text.contains("yesterday") ? -1 : 0, targets: targets))
    }

    /// Exactly one "<n> mg" amount, as `caffeineDraft` reads it; two or more give nil.
    /// A token `MgToken` can't read (signed, grouped, malformed) comes back
    /// as NaN, which fails `CaffeineLog.isValidAmount`, so the route asks
    /// again (`.clarify`) instead of keeping its trailing digits.
    static func singleMg(_ text: String) -> Double? {
        let found = MgToken.matches(in: text)
        guard found.count == 1 else { return nil }
        return found[0].value ?? .nan
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
