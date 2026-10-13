import Foundation

/// Whether Aurora follows up on yesterday's drinks, and whether it also
/// notifies. Off unless the person turns it on.
public struct RepeatDrinkSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var notify: Bool

    public static let off = RepeatDrinkSettings(enabled: false, notify: false)

    public init(enabled: Bool, notify: Bool) {
        self.enabled = enabled
        self.notify = notify
    }
}

/// Next-day follow-ups: for a drink logged in Aurora yesterday, a question
/// at the same local time today, "Had your 9:30 Drip today?". It asks about
/// recording, never suggests drinking, and opens a draft for review.
public enum RepeatDrinks {
    public static let dailyLimit = 3
    /// A follow-up stays in the conversation this long after its time.
    public static let windowMs: Millis = 4 * hourMs
    /// A drink of the same kind already logged this close to the time today
    /// answers the question, so none is asked.
    public static let alreadyLoggedMs: Millis = 90 * minuteMs
    public static let keyPrefix = "repeat:"
    public static let notificationPrefix = "repeat-drink-"

    public struct Prompt: Codable, Equatable, Identifiable, Sendable {
        /// Yesterday's dose.
        public var doseID: String
        public var source: String?
        public var mg: Double
        /// When it was logged yesterday.
        public var yesterdayAt: Millis
        /// The same local wall-clock time today.
        public var dueAt: Millis
        public var id: String { RepeatDrinks.key(doseID: doseID) }
        public var expiresAt: Millis { dueAt + RepeatDrinks.windowMs }
        public var notificationID: String { RepeatDrinks.notificationPrefix + doseID }
    }

    public static func key(doseID: String) -> String { keyPrefix + doseID }

    /// Today's follow-ups from yesterday's drinks, earliest first: drinks
    /// logged in Aurora (not Sample Data, not Health caffeine from other
    /// apps), at most one per kind of drink within 90 minutes, none already
    /// answered by a drink of that kind logged around the time today, and
    /// at most `dailyLimit`.
    public static func planned(doses: [Dose], now: Millis, clock: LocalClock) -> [Prompt] {
        let today = clock.startOfDay(now)
        let yesterday = clock.addingDays(-1, to: today)
        let candidates = doses
            .filter { $0.timestamp >= yesterday && $0.timestamp < today && $0.mg > 0 }
            .filter { !RecordID.isSample($0.id) && !RecordID.isHealthCaffeine($0.id) }
            .sorted { $0.timestamp != $1.timestamp ? $0.timestamp < $1.timestamp : $0.id < $1.id }
        var prompts: [Prompt] = []
        for dose in candidates {
            let kind = Insights.normalizeDrink(dose.source)
            // Two coffees half an hour apart yesterday ask once.
            if prompts.contains(where: { Insights.normalizeDrink($0.source) == kind && dose.timestamp - $0.yesterdayAt < alreadyLoggedMs }) { continue }
            let parts = clock.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: dose.timestamp / 1000))
            let due = clock.setTime(today, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            let answered = doses.contains {
                !RecordID.isSample($0.id) && $0.timestamp >= today && abs($0.timestamp - due) <= alreadyLoggedMs
                    && Insights.normalizeDrink($0.source) == kind
            }
            if answered { continue }
            prompts.append(Prompt(doseID: dose.id, source: dose.source, mg: dose.mg, yesterdayAt: dose.timestamp, dueAt: due))
        }
        return Array(prompts.prefix(dailyLimit))
    }

    /// Follow-ups to show in the conversation now: their time has come and
    /// not passed by more than the window, they weren't shown or dismissed,
    /// and it isn't quiet hours.
    public static func due(_ prompts: [Prompt], conversation: ConversationState, now: Millis, clock: LocalClock) -> [Prompt] {
        guard !ProactivePolicy.isQuiet(hour: clock.hour(now), preferences: conversation.preferences) else { return [] }
        return prompts.filter {
            $0.dueAt <= now && now < $0.expiresAt
                && conversation.deliveredSuggestions[$0.id] == nil && !conversation.dismissedSuggestions.contains($0.id)
        }
    }

    /// Follow-ups still ahead today, for notifications: not dismissed, not
    /// already shown, and not falling in quiet hours.
    public static func upcoming(_ prompts: [Prompt], conversation: ConversationState, now: Millis, clock: LocalClock) -> [Prompt] {
        prompts.filter {
            $0.dueAt > now && conversation.deliveredSuggestions[$0.id] == nil && !conversation.dismissedSuggestions.contains($0.id)
                && !ProactivePolicy.isQuiet(hour: clock.hour($0.dueAt), preferences: conversation.preferences)
        }
    }

    /// "Had your 9:30 Drip today?"
    public static func question(_ prompt: Prompt, text: DateText) -> String {
        "Had your \(text.clockTime(prompt.yesterdayAt)) \(drinkName(prompt)) today?"
    }

    /// "Yesterday · 95 mg"
    public static func detail(_ prompt: Prompt) -> String {
        "Yesterday · \(numberText(prompt.mg)) mg"
    }

    static func drinkName(_ prompt: Prompt) -> String {
        let source = (prompt.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? "caffeine" : source
    }

    /// The draft a follow-up opens: yesterday's drink and amount, timed now,
    /// for review before saving.
    public static func draft(_ prompt: Prompt, now: Millis) -> CustomDoseDraft {
        CustomDoseDraft(mg: numberText(prompt.mg), source: prompt.source ?? "", timestamp: now, note: "")
    }
}
