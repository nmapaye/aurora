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
        let pattern = #"^(?:i had|i drank|log)\s+(?:one\s+)?"# + amount + drink + time + #"[.!]?$"#
        guard let parts = captures(pattern, text), parts.count == 3 else {
            return .clarify("Please name one drink, its caffeine amount in mg, and when you had it; or use manual Log caffeine.")
        }
        let amountSpan = parts[0], drinkSpan = parts[1], timeSpan = parts[2]
        guard !timeSpan.isEmpty else { return .clarify("When did you have this drink? Say now or a local time such as yesterday at 8am.") }
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
