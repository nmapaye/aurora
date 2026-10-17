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
/// about an hour after that time today, "Did you have a Drip around 9:30?".
/// Asking after, not at, the usual time keeps it a recall prompt rather than
/// a cue to have the drink. It asks about recording, never suggests
/// drinking, and opens a draft for review. "Not today" records nothing:
/// a missing record is not zero.
///
/// Notifications are one silent batch a day with no amounts, nothing at or
/// after the person's cutoff time, and none after `pauseAfterIgnoredDays`
/// days in a row with no follow-up answered.
public enum RepeatDrinks {
    public static let dailyLimit = 3
    /// A follow-up is asked this long after yesterday's time.
    public static let followUpDelayMs: Millis = 60 * minuteMs
    /// A follow-up stays in the conversation until this long after
    /// yesterday's time (three hours after it is asked).
    public static let windowMs: Millis = 4 * hourMs
    /// A drink of the same kind already logged this close to yesterday's
    /// time today answers the question, so none is asked.
    public static let alreadyLoggedMs: Millis = 90 * minuteMs
    /// Notifications stop after this many days in a row with follow-ups
    /// offered and none answered.
    public static let pauseAfterIgnoredDays = 5
    public static let keyPrefix = "repeat:"
    public static let notificationPrefix = "repeat-drink-"
    public static let notificationTitle = "Log yesterday’s drinks?"

    public struct Prompt: Codable, Equatable, Identifiable, Sendable {
        /// Yesterday's dose.
        public var doseID: String
        public var source: String?
        public var mg: Double
        /// When it was logged yesterday.
        public var yesterdayAt: Millis
        /// When it is asked today: `followUpDelayMs` after the same local
        /// wall-clock time.
        public var dueAt: Millis
        public init(doseID: String, source: String?, mg: Double, yesterdayAt: Millis, dueAt: Millis) {
            self.doseID = doseID; self.source = source; self.mg = mg; self.yesterdayAt = yesterdayAt; self.dueAt = dueAt
        }
        public var id: String { RepeatDrinks.key(doseID: doseID) }
        /// Yesterday's wall-clock time, today.
        public var sameTimeAt: Millis { dueAt - RepeatDrinks.followUpDelayMs }
        public var expiresAt: Millis { sameTimeAt + RepeatDrinks.windowMs }
    }

    public static func key(doseID: String) -> String { keyPrefix + doseID }

    /// Today's follow-ups from yesterday's drinks, earliest first: drinks
    /// logged in Aurora (not Sample Data, not Health caffeine from other
    /// apps), at most one per kind of drink within 90 minutes, none already
    /// answered by a drink of that kind logged around the time today, none
    /// asked at or after the person's cutoff time, and at most `dailyLimit`.
    public static func planned(doses: [Dose], now: Millis, clock: LocalClock, cutoffHour: Double? = nil) -> [Prompt] {
        let today = clock.startOfDay(now)
        let yesterday = clock.addingDays(-1, to: today)
        let cutoff = CutoffTime.at(dayStart: today, hour: cutoffHour, clock: clock)
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
            let sameTime = clock.setTime(today, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            let due = sameTime + followUpDelayMs
            if let cutoff, due >= cutoff { continue }
            if answers(doses, kind: kind, around: sameTime, from: today) { continue }
            prompts.append(Prompt(doseID: dose.id, source: dose.source, mg: dose.mg, yesterdayAt: dose.timestamp, dueAt: due))
        }
        return Array(prompts.prefix(dailyLimit))
    }

    /// A drink of `kind` logged in Aurora since `from`, within
    /// `alreadyLoggedMs` of `around`.
    static func answers(_ doses: [Dose], kind: String, around: Millis, from: Millis) -> Bool {
        doses.contains {
            !RecordID.isSample($0.id) && $0.timestamp >= from && abs($0.timestamp - around) <= alreadyLoggedMs
                && Insights.normalizeDrink($0.source) == kind
        }
    }

    /// Follow-ups to show in the conversation now: their time has come and
    /// not passed by more than the window, they weren't shown or dismissed,
    /// and it isn't quiet hours or past the person's cutoff time.
    public static func due(_ prompts: [Prompt], conversation: ConversationState, now: Millis, clock: LocalClock, cutoffHour: Double? = nil) -> [Prompt] {
        guard !ProactivePolicy.isQuiet(hour: clock.hour(now), preferences: conversation.preferences) else { return [] }
        if let cutoff = CutoffTime.at(dayStart: clock.startOfDay(now), hour: cutoffHour, clock: clock), now >= cutoff { return [] }
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

    // MARK: Copy

    /// "Did you have a Drip around 9:30?" Past tense, about recording.
    public static func question(_ prompt: Prompt, text: DateText) -> String {
        let source = trimmedSource(prompt)
        let drink = source.isEmpty ? "caffeine" : "\(article(source)) \(source)"
        return "Did you have \(drink) around \(text.clockTime(prompt.yesterdayAt))?"
    }

    /// "Yesterday · 95 mg", in the conversation only, never on the lock
    /// screen.
    public static func detail(_ prompt: Prompt) -> String {
        "Yesterday · \(numberText(prompt.mg)) mg"
    }

    static func trimmedSource(_ prompt: Prompt) -> String {
        (prompt.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func drinkName(_ prompt: Prompt) -> String {
        let source = trimmedSource(prompt)
        return source.isEmpty ? "Caffeine" : source
    }

    static func article(_ word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    /// The draft a follow-up opens: yesterday's drink and amount, timed now,
    /// for review before saving.
    public static func draft(_ prompt: Prompt, now: Millis) -> CustomDoseDraft {
        CustomDoseDraft(mg: numberText(prompt.mg), source: prompt.source ?? "", timestamp: now, note: "")
    }

    // MARK: Notifications

    /// Today's one follow-up notification: silent, at the latest due time
    /// among `upcoming`, naming every follow-up still open then. No amounts.
    public struct Batch: Codable, Equatable, Sendable {
        /// Local midnight of the day it belongs to.
        public var dayStart: Millis
        public var fireAt: Millis
        public var prompts: [Prompt]
        public var identifier: String

        public init(dayStart: Millis, fireAt: Millis, prompts: [Prompt], identifier: String) {
            self.dayStart = dayStart; self.fireAt = fireAt; self.prompts = prompts; self.identifier = identifier
        }
    }

    public static func batch(_ upcoming: [Prompt], clock: LocalClock) -> Batch? {
        guard let fireAt = upcoming.map(\.dueAt).max() else { return nil }
        let open = upcoming.filter { $0.dueAt <= fireAt && fireAt < $0.expiresAt }
        let dayStart = clock.startOfDay(fireAt)
        return Batch(dayStart: dayStart, fireAt: fireAt, prompts: open, identifier: notificationPrefix + clock.dayKey(dayStart))
    }

    /// "Drip · around 9:30." One line per drink.
    public static func notificationBody(_ batch: Batch, text: DateText) -> String {
        batch.prompts.map { "\(drinkName($0)) · around \(text.clockTime($0.yesterdayAt))." }.joined(separator: "\n")
    }

    // MARK: Pausing when ignored

    /// Which days had follow-ups and whether any was answered, so
    /// notifications pause after `pauseAfterIgnoredDays` unanswered days in
    /// a row. A day counts once a follow-up card was shown or its
    /// notification's time passed. It is answered by "Log it", or by a drink
    /// of that kind logged around the time. "Not today" and letting it
    /// expire don't answer it. Days with no follow-ups don't count either way.
    public struct Engagement: Codable, Equatable, Sendable {
        public struct Day: Codable, Equatable, Sendable {
            public var dayStart: Millis
            public var prompts: [Prompt]
            public var answered: Bool

            public init(dayStart: Millis, prompts: [Prompt], answered: Bool = false) {
                self.dayStart = dayStart; self.prompts = prompts; self.answered = answered
            }
        }

        /// Most recent last; days older than two weeks are dropped.
        public var days: [Day]
        /// The notification last handed to the system.
        public var scheduled: Batch?

        public init(days: [Day] = [], scheduled: Batch? = nil) {
            self.days = days
            self.scheduled = scheduled
        }

        public mutating func recordOffered(_ prompts: [Prompt], now: Millis, clock: LocalClock) {
            guard !prompts.isEmpty else { return }
            add(prompts, dayStart: clock.startOfDay(now))
            prune(now: now, clock: clock)
        }

        public mutating func recordAnswered(now: Millis, clock: LocalClock) {
            let start = clock.startOfDay(now)
            if let index = days.firstIndex(where: { $0.dayStart == start }) {
                days[index].answered = true
            } else {
                days.append(Day(dayStart: start, prompts: [], answered: true))
                days.sort { $0.dayStart < $1.dayStart }
            }
        }

        /// A scheduled notification whose time has passed was delivered:
        /// its follow-ups count as offered that day.
        public mutating func settle(now: Millis, clock: LocalClock) {
            if let batch = scheduled, batch.fireAt <= now {
                add(batch.prompts, dayStart: batch.dayStart)
                scheduled = nil
            }
            prune(now: now, clock: clock)
        }

        /// Offered days in a row, most recent first, with nothing answered.
        /// Today counts only once it is over or answered.
        public func unansweredStreak(doses: [Dose], now: Millis, clock: LocalClock) -> Int {
            let today = clock.startOfDay(now)
            var streak = 0
            for day in days.reversed() where !day.prompts.isEmpty || day.answered {
                let answered = day.answered || day.prompts.contains {
                    RepeatDrinks.answers(doses, kind: Insights.normalizeDrink($0.source), around: $0.sameTimeAt, from: day.dayStart)
                }
                if answered { break }
                if day.dayStart >= today { continue }
                streak += 1
            }
            return streak
        }

        public func isPaused(doses: [Dose], now: Millis, clock: LocalClock) -> Bool {
            unansweredStreak(doses: doses, now: now, clock: clock) >= RepeatDrinks.pauseAfterIgnoredDays
        }

        private mutating func add(_ prompts: [Prompt], dayStart: Millis) {
            if let index = days.firstIndex(where: { $0.dayStart == dayStart }) {
                let known = Set(days[index].prompts.map(\.id))
                days[index].prompts += prompts.filter { !known.contains($0.id) }
            } else {
                days.append(Day(dayStart: dayStart, prompts: prompts))
                days.sort { $0.dayStart < $1.dayStart }
            }
        }

        private mutating func prune(now: Millis, clock: LocalClock) {
            let oldest = clock.addingDays(-14, to: clock.startOfDay(now))
            days.removeAll { $0.dayStart < oldest }
        }
    }
}
