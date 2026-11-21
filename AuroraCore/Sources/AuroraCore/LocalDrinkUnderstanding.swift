import Foundation

/// Deliberately small supported language. The model extracts spans/intent, never
/// record values. Full-input matching is the independent provenance boundary;
/// range checks alone do not authorize a model-produced number.
public enum LocalDrinkUnderstanding {
    public static let autosaveEnabled = false // No settings or runtime override.

    public struct Evidence: Equatable, Sendable {
        public let route: String
        public let drink: String
        public let amount: String
        public let time: String
        public init(route: String, drink: String, amount: String, time: String) {
            self.route = route; self.drink = drink; self.amount = amount; self.time = time
        }
    }
    public struct Proposal: Equatable, Sendable {
        public let draft: CustomDoseDraft
        public let evidence: Evidence
        public let provenance: String
        public let timeZone: String
    }
    public enum Result: Equatable, Sendable {
        case proposal(Proposal), clarify(String)
    }
    public static func isDrinkRequest(_ text: String) -> Bool {
        normalized(text).range(of: #"\b(coffee|caffeine|espresso|espressos|drip|tea|matcha|cold brew|energy drink|usual)\b"#, options: .regularExpression) != nil
    }
    /// Known capabilities take precedence. Only positive consumed-drink or
    /// direct log intent may enter the new path; a generic drink keyword in a
    /// question is NOT a logging instruction.
    public static func shouldUnderstand(_ input: String, knownIntent: AssistantIntent?) -> Bool {
        let text = normalized(input)
        if let knownIntent, knownIntent != .logCaffeine { return false }
        guard text != "log caffeine" else { return false }
        let direct = text.range(of: #"^(?:i had|i drank|log)\s+"#, options: .regularExpression) != nil
        return direct && isDrinkRequest(text)
    }
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
    /// Questions whose one-word answer completes the drink just named.
    public static let timeQuestion = "When did you have this drink? Say now or a local time such as yesterday at 8am."
    public static func asksForAmount(_ question: String) -> Bool { question.hasPrefix("What caffeine amount in mg") }

    /// The pending request completed by a short answer to `timeQuestion` or an
    /// amount question ("now", "yesterday at 8am", "95 mg", "95"), or nil when
    /// the answer is anything else. Held in memory for one reply only; the
    /// combined text goes through `prepare` like any typed request.
    public static func answering(_ original: String, with answer: String) -> String? {
        let request = normalized(original).trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let reply = normalized(answer).trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        guard request.range(of: #"^(?:i had|i drank|log)\s+"#, options: .regularExpression) != nil else { return nil }
        let time = #"^(now|(?:yesterday |today )?at (?:1[0-2]|[1-9])(?::[0-5][0-9])?\s*(?:am|pm))$"#
        if reply.range(of: time, options: .regularExpression) != nil {
            return request + " " + reply
        }
        if let parts = captures(#"^(\d+(?:\.\d+)?)\s*(mg|g)?$"#, reply) {
            let amount = parts[0] + " " + (parts[1].isEmpty ? "mg" : parts[1])
            guard let regex = try? NSRegularExpression(pattern: #"^(i had|i drank|log)\s+(?:(?:one|a|an)\s+)?"#) else { return nil }
            let range = NSRange(request.startIndex..., in: request)
            return regex.stringByReplacingMatches(in: request, range: range, withTemplate: "$1 " + amount + " ")
        }
        return nil
    }

    /// A typed drink to choose in the database chooser (the photo sheet's
    /// review, without a photo).
    public struct DatabaseLookup: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let phrase: String
        public let timestamp: Millis
        /// Set when this corrects a saved dose: Save updates that dose.
        public let replacing: String?
        public init(phrase: String, timestamp: Millis, replacing: String? = nil) {
            self.phrase = phrase; self.timestamp = timestamp; self.replacing = replacing
        }
        public static func == (a: Self, b: Self) -> Bool { a.phrase == b.phrase && a.timestamp == b.timestamp && a.replacing == b.replacing }
    }

    /// The drink named in a correction of the last entry: "change the last
    /// entry to matcha", "adjust my last drink to a latte", "that was a
    /// matcha", "it was actually green tea". Nil for anything else.
    public static func lastEntryCorrection(_ input: String, db: CaffeineDatabase?) -> String? {
        let text = normalized(input).trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let patterns = [
            #"^(?:please\s+)?(?:change|adjust|edit|update|fix|correct|switch|make)\s+(?:the\s+|my\s+|that\s+)?(?:last|latest|previous|recent|most recent)?\s*(?:entry|drink|one|log|caffeine|dose)\s+(?:to|into|as|so it'?s)\s+(?:an?\s+)?(.+)$"#,
            #"^(?:that|it)\s+was\s+(?:actually\s+)?(?:an?\s+)?(.+?)(?:\s+not\s+.+)?$"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let parts = captures(pattern, text), let drink = parts.first?.trimmingCharacters(in: .whitespaces), !drink.isEmpty,
                  drink.split(separator: " ").count <= 5, !drink.contains("?") else { continue }
            // "It was great" isn't a drink: the short form needs one Aurora knows.
            if index == 1 {
                let known = DrinkPhotoMatcher.unrecordedBrand(in: drink) != nil
                    || drink.range(of: TypedDrinkEntry.drinkWords, options: .regularExpression) != nil
                    || (db.map { !DrinkPhotoMatcher.search(drink, in: $0).isEmpty } ?? false)
                guard known else { continue }
            }
            return drink
        }
        return nil
    }

    /// "Change the last entry", "edit my last drink", "fix that entry": a
    /// correction that names no drink yet.
    public static func isBareLastEntryEdit(_ input: String) -> Bool {
        let text = normalized(input).trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        return text.range(of: #"^(?:please\s+)?(?:change|adjust|edit|update|fix|correct)\s+(?:the\s+|my\s+|that\s+)?(?:last|latest|previous|recent|most recent)?\s*(?:entry|drink|one|log|caffeine|dose)$"#, options: .regularExpression) != nil
    }

    /// The dose a correction applies to: the newest one Aurora may edit
    /// (never a Health import). Nil when there is none.
    public static func correctionTarget(_ doses: [Dose]) -> Dose? {
        doses.filter(CaffeineLog.isEditable).max { $0.timestamp < $1.timestamp }
    }

    public enum DatabaseRoute: Equatable, Sendable {
        /// One record (or a Not in Database brand): the filled entry card.
        case entry(TypedDrinkEntry.Entry)
        /// Several records match: pick one with its sizes.
        case choose(DatabaseLookup)
    }

    /// With Apple Intelligence on, a logged drink the verified path would
    /// only answer with a question ("I had a Red Bull", "I drank green tea",
    /// "log a celsius yesterday at 8am") goes to the bundled database: one
    /// record fills the entry card, several open the chooser. Complete
    /// verified requests keep their path. Nil when the text doesn't lead
    /// with "I had", "I drank" or "log", or no drink is found.
    public static func databaseRoute(_ input: String, doses: [Dose], db: CaffeineDatabase?, now: Millis, clock: LocalClock) -> DatabaseRoute? {
        let text = normalized(input)
        guard text.range(of: #"^(?:i\s+)?(?:just\s+)?(?:had|drank|log|logged)\s+"#, options: .regularExpression) != nil else { return nil }
        if case .proposal = prepare(input, doses: doses, now: now, clock: clock) { return nil }
        guard case .entry(let entry)? = TypedDrinkEntry.parse(input, db: db, now: now, clock: clock) else { return nil }
        if entry.amountSource != .none { return .entry(entry) }
        if DrinkPhotoMatcher.unrecordedBrand(in: entry.draft.source) != nil { return .entry(entry) }
        if let db, !DrinkPhotoMatcher.search(entry.draft.source, in: db).isEmpty {
            return .choose(DatabaseLookup(phrase: entry.draft.source, timestamp: entry.draft.timestamp))
        }
        return .entry(entry)
    }

    public static func prepare(_ input: String, doses: [Dose], now: Millis, clock: LocalClock) -> Result {
        let text = normalized(input)
        // Multi never becomes a partial success, including counts and repeats.
        if text.range(of: #"\b(and|then|two|three|both|another)\b|\b[2-9]\s+(?:espresso|coffee|tea|drink)"#, options: .regularExpression) != nil {
            return .clarify("One drink at a time. Which drink would you like to record first?")
        }
        // This is a whitelist, not a safety blacklist. Quotes, negation, advice,
        // hypothetical speech, corrections and trailing instructions fail closed.
        let drink = #"(my usual|espresso|drip(?: coffee)?|matcha|energy drink|coffee|caffeine|tea|cold brew)"#
        let amount = #"(?:(-?\d+(?:\.\d+)?\s*(?:mg|g))\s+)?"#
        let time = #"(?:\s+(now|(?:yesterday |today )?at (?:1[0-2]|[1-9])(?::[0-5][0-9])?\s*(?:am|pm)))?"#
        let pattern = #"^(?:i had|i drank|log)\s+(?:(?:one|a|an)\s+)?"# + amount + drink + time + #"[.!]?$"#
        guard let parts = captures(pattern, text), parts.count == 3 else {
            return .clarify("Please name one drink, its caffeine amount in mg, and when you had it; or use manual Log caffeine.")
        }
        let amountSpan = parts[0], drinkSpan = parts[1], timeSpan = parts[2]
        guard !timeSpan.isEmpty else { return .clarify(timeQuestion) }
        let source: String
        let mg: Double
        let provenance: String
        let usual = drinkSpan == "my usual" ? AssistantPlanner.usual(doses, now: now) : nil
        if drinkSpan == "my usual", usual == nil {
            return .clarify("Which drink and caffeine amount in mg did you have? No recorded usual is available.")
        }
        source = usual?.source ?? ["espresso": "Espresso", "drip": "Drip", "drip coffee": "Drip", "matcha": "Matcha",
                                  "energy drink": "Energy", "coffee": "Coffee", "caffeine": "Caffeine", "tea": "Tea", "cold brew": "Cold Brew"][drinkSpan] ?? ""
        if !amountSpan.isEmpty {
            guard let parts = captures(#"^(-?\d+(?:\.\d+)?)\s*(mg|g)$"#, amountSpan), let value = Double(parts[0]) else {
                return .clarify("What caffeine amount in mg did you have?")
            }
            mg = value * (parts[1] == "g" ? 1000 : 1)
            provenance = parts[1] == "g" ? "Typed amount · g converted to mg" : "Typed amount · mg"
        } else if let usual {
            mg = usual.mg
            provenance = "Recorded usual · " + CaffeineLog.sourceLabel(usual)
        } else if let preset = CaffeinePreset.all.first(where: { $0.label == source }) {
            mg = preset.mg; provenance = "Aurora preset · " + preset.label
        } else {
            return .clarify("What caffeine amount in mg did you have? There is no verified amount for this drink.")
        }
        guard mg.isFinite, mg >= 1, mg <= 1999, mg.rounded() == mg else {
            return .clarify("What whole caffeine amount between 1 and 1999 mg did you have?")
        }
        let timestamp: Millis
        if timeSpan == "now" { timestamp = now }
        else {
            guard let resolved = AssistantPlanner.mentionedTime(timeSpan, now: now, clock: clock), resolved <= now,
                  let parts = captures(#"(?:^| )at (1[0-2]|[1-9])(?::([0-5][0-9]))?\s*(am|pm)$"#, timeSpan),
                  let hour = Int(parts[0]) else { return .clarify("What past local date and time did you have this drink?") }
            // Calendar may normalize a nonexistent DST wall time. Do not accept it.
            let date = Date(timeIntervalSince1970: resolved / 1000)
            let components = clock.calendar.dateComponents([.hour, .minute], from: date)
            guard components.hour == hour % 12 + (parts[2] == "pm" ? 12 : 0), components.minute == (Int(parts[1]) ?? 0) else {
                return .clarify("That local time does not exist. What time did you have this drink?")
            }
            // Repeated DST hours are ambiguous; ask instead of choosing silently.
            let sameWallTime = [-2 * hourMs, -hourMs, -30 * minuteMs, 30 * minuteMs, hourMs, 2 * hourMs].contains { offset in
                let other = resolved + offset
                let c = clock.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: other / 1000))
                return clock.dayKey(other) == clock.dayKey(resolved) && c.hour == components.hour && c.minute == components.minute
            }
            guard !sameWallTime else { return .clarify("That local time occurs twice. Please use manual Log caffeine to choose the exact time.") }
            timestamp = resolved
        }
        let draft = CustomDoseDraft(mg: numberText(mg), source: source, timestamp: timestamp, note: "")
        guard CaffeineLog.validate(draft, now: now) == .valid else { return .clarify("Please check the caffeine amount and past local time.") }
        return .proposal(.init(draft: draft, evidence: .init(route: "log", drink: drinkSpan, amount: amountSpan, time: timeSpan),
                               provenance: provenance, timeZone: clock.timeZone.identifier))
    }
    public static func validate(_ extracted: Evidence, against proposal: Proposal) -> Bool {
        extracted == proposal.evidence
    }
}

/// Ephemeral immutable review, owned by the main-actor assistant. Nothing here
/// writes. A failed persistence keeps the snapshot available for an explicit retry.
public struct LocalDrinkReview: Sendable {
    public private(set) var request: UUID?
    public private(set) var proposal: LocalDrinkUnderstanding.Proposal?
    public init() {}
    public mutating func begin(_ id: UUID) { request = id; proposal = nil }
    public mutating func cancel() { request = nil; proposal = nil }
    @discardableResult public mutating func offer(_ value: LocalDrinkUnderstanding.Proposal, request id: UUID) -> Bool {
        guard request == id, proposal == nil else { return false }
        proposal = value; return true
    }
    public func canSave(_ draft: CustomDoseDraft) -> Bool { request != nil && proposal?.draft == draft }
    public mutating func didPersist() { cancel() }
}
