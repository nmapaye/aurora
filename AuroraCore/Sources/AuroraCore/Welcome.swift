import Foundation

/// The welcome shown when Aurora opens, and first-run setup order. Everything
/// here describes records; nothing suggests what to do.
public enum Welcome {
    /// Local time of day. Morning starts at 5:00, afternoon at 12:00,
    /// evening at 18:00; before 5:00 is night.
    public enum Daypart: String, Sendable, CaseIterable {
        case night, morning, afternoon, evening

        public init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<18: self = .afternoon
            case 18..<24: self = .evening
            default: self = .night
            }
        }
    }

    public static func greeting(daypart: Daypart, name: String?) -> String {
        let base = switch daypart {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening: "Good evening"
        case .night: "Hello"
        }
        guard let name = cleanName(name) else { return base }
        return "\(base), \(name)"
    }

    public static let nameLimit = 40

    /// Trims, collapses inner whitespace and caps the length. Empty is nil.
    public static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let joined = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(nameLimit))
    }

    /// Shown under the greeting when no record applies. Not evidence.
    public static let neutralLine = "Ready when you are."

    /// One recorded fact for the greeting, always with its source and time.
    /// Only sleep and caffeine already saved in Aurora qualify: no calendar
    /// events, estimates or projections, which could be stale or read as
    /// advice.
    public struct Evidence: Equatable, Sendable {
        public enum Kind: String, Sendable { case lastSleep, caffeineToday }

        public var kind: Kind
        public var text: String
        /// When it was recorded, e.g. "Ended today, 6:42 AM".
        public var date: String
        /// "Health", "Manual", "Sample Data", or several joined with " · ".
        public var source: String
        /// True when any record behind this line is Sample Data.
        public var sample: Bool
        /// SF Symbol name.
        public var symbol: String

        public var spoken: String { "\(text). \(date). Source: \(source)." }
    }

    public static let sleepWindowMs: Millis = 6 * hourMs

    /// First match wins: sleep (not a nap) that ended in the last six hours,
    /// then caffeine recorded so far today. Nil when neither exists, so a
    /// missing record is never shown as zero.
    public static func evidence(state: AppState, now: Millis, clock: LocalClock, text: DateText) -> Evidence? {
        func when(_ ms: Millis) -> String {
            clock.startOfDay(ms) == clock.startOfDay(now) ? "today, \(text.clockTime(ms))" : "\(text.shortDate(ms)), \(text.clockTime(ms))"
        }
        if let sleep = state.sleeps
            .filter({ $0.type == .sleep && $0.end <= now && $0.end > now - sleepWindowMs && $0.end > $0.start })
            .max(by: { $0.end < $1.end }) {
            return Evidence(
                kind: .lastSleep,
                text: "\(formatHoursMinutes(durationMs: sleep.end - sleep.start)) of recorded sleep",
                date: "Ended \(when(sleep.end))",
                source: SleepModel.sourceLabel(id: sleep.id),
                sample: RecordID.isSample(sleep.id),
                symbol: "moon.stars"
            )
        }
        let today = state.doses.filter { $0.timestamp >= clock.startOfDay(now) && $0.timestamp <= now && $0.mg > 0 }
        if let last = today.max(by: { $0.timestamp < $1.timestamp }) {
            let order = ["Health", "Manual", "Sample Data"]
            let sources = Set(today.map(CaffeineLog.sourceLabel)).sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            return Evidence(
                kind: .caffeineToday,
                text: "\(numberText(today.reduce(0) { $0 + $1.mg })) mg of caffeine recorded today",
                date: "Last \(when(last.timestamp))",
                source: sources.joined(separator: " · "),
                sample: today.contains { RecordID.isSample($0.id) },
                symbol: "cup.and.saucer"
            )
        }
        return nil
    }

    /// Whether the welcome covers the conversation, and whether it may take
    /// touches. Skipping is synchronous: the conversation is usable in the
    /// same update, and any fade afterwards is decoration only.
    public struct Presentation: Equatable, Sendable {
        public private(set) var showing: Bool

        /// How long the welcome stays before ending by itself. A tap ends it
        /// sooner; it never has to finish before the conversation works.
        public static let holdSeconds = 1.2

        /// Once per cold launch, only for people who finished setup. Not
        /// shown under VoiceOver, so focus starts in the conversation and
        /// nothing is announced twice.
        public static func atLaunch(onboardingCompleted: Bool, voiceOverRunning: Bool) -> Presentation {
            Presentation(showing: onboardingCompleted && !voiceOverRunning)
        }

        public var blocksInteraction: Bool { showing }
        public var hidesConversationFromAccessibility: Bool { showing }

        public mutating func skip() { showing = false }
    }
}

extension CaffeinePreset {
    /// Favorites first, in the order picked, then the rest in their usual
    /// order. Unknown ids are ignored.
    public static func ordered(favorites: [String]?) -> [CaffeinePreset] {
        var seen = Set<String>()
        let picked = (favorites ?? []).compactMap { id in all.first { $0.id == id } }.filter { seen.insert($0.id).inserted }
        return picked + all.filter { !seen.contains($0.id) }
    }
}

/// First-run setup questions, asked one at a time. Every one can be skipped.
/// Raw values are stored in `Onboarding.setupStep`; gaps are retired
/// questions (1 favorite drinks, 3 sleep source), and a stored gap resumes
/// at the next question still asked.
public enum SetupStep: Int, CaseIterable, Sendable {
    case name = 0
    case sleepTarget = 2
    case health = 4
    case calendar = 5
    case finish = 6

    public var next: SetupStep {
        Self.allCases.first { $0.rawValue > rawValue } ?? .finish
    }

    /// A stored step. Nil starts at the beginning; anything past the end, or
    /// from another build, is clamped.
    public init(stored: Int?) {
        let value = max(stored ?? 0, 0)
        self = Self.allCases.first { $0.rawValue >= value } ?? .finish
    }
}

/// What the person did when a setup question was asked.
public enum SetupOutcome: String, Sendable {
    /// They gave or confirmed an answer.
    case answered
    /// They tapped "Not now"; whatever was already stored stays.
    case skipped
}

extension Onboarding {
    /// The recorded outcome for a step. Unknown values from another build
    /// read as nil. A display name only ever comes from the name question,
    /// so files from before outcomes were kept treat a stored name as
    /// answered.
    public func setupOutcome(_ step: SetupStep, displayName: String?) -> SetupOutcome? {
        if let raw = setupOutcomes?[String(step.rawValue)], let outcome = SetupOutcome(rawValue: raw) { return outcome }
        if step == .name, displayName != nil { return .answered }
        return nil
    }
}

extension AppState {
    /// Records the outcome for `step` and moves to the next question in one
    /// change, so an answer and its progress are saved together or not at all.
    public mutating func recordSetup(_ step: SetupStep, _ outcome: SetupOutcome) {
        var outcomes = onboarding.setupOutcomes ?? [:]
        outcomes[String(step.rawValue)] = outcome.rawValue
        onboarding.setupOutcomes = outcomes
        onboarding.setupStep = step.next.rawValue
    }

    /// "Skip to the end": goes to the last step. Questions not asked get no
    /// outcome, so nothing is shown as an answer for them.
    public mutating func skipSetupToEnd() {
        settleSetupSleepSource()
        onboarding.setupStep = SetupStep.finish.rawValue
    }

    /// Without Health sleep, sleep is logged by hand. A declined request has
    /// already set manual with its own status, which is kept.
    public mutating func settleSetupSleepSource() {
        guard onboarding.source == .healthkit, !healthChoices.readSleep else { return }
        onboarding.source = .manual
        onboarding.permissionStatus = .unsupported
    }
}

/// The setup conversation, built only from what was asked and recorded.
public enum SetupTranscript {
    public enum Reply: Equatable, Sendable {
        /// Something the person actually chose or typed.
        case person(String)
        /// A note from Aurora about a setting that stayed as it was.
        case retained(String)
    }

    public struct Entry: Equatable, Sendable {
        public var step: SetupStep
        public var question: String
        public var reply: Reply?
    }

    /// Asked questions in order with their real outcomes, then the current
    /// question. Questions with no recorded outcome (passed over by "Skip to
    /// the end", or never reached) are left out rather than given an answer.
    public static func entries(
        state: AppState,
        healthAvailable: Bool,
        calendarsChosen: Bool,
        modelAvailable: Bool
    ) -> [Entry] {
        let current = SetupStep(stored: state.onboarding.setupStep)
        var entries: [Entry] = []
        for step in SetupStep.allCases where step.rawValue < current.rawValue {
            guard let outcome = state.onboarding.setupOutcome(step, displayName: state.prefs.displayName) else { continue }
            entries.append(Entry(step: step, question: SetupCopy.question(step, modelAvailable: modelAvailable),
                                 reply: reply(step, outcome, state: state, healthAvailable: healthAvailable, calendarsChosen: calendarsChosen)))
        }
        entries.append(Entry(step: current, question: SetupCopy.question(current, modelAvailable: modelAvailable), reply: nil))
        return entries
    }

    static func reply(_ step: SetupStep, _ outcome: SetupOutcome, state: AppState, healthAvailable: Bool, calendarsChosen: Bool) -> Reply? {
        let target = OnboardingCopy.formatSleepTarget(state.prefs.targetSleep).spoken
        switch (step, outcome) {
        case (.name, .answered): return state.prefs.displayName.map(Reply.person)
        case (.sleepTarget, .answered): return .person(target)
        case (.sleepTarget, .skipped): return .retained("Sleep target stays at \(target). You can change it in Settings.")
        case (.health, .answered): return .person(SetupCopy.healthAnswer(state.healthChoices, healthAvailable: healthAvailable))
        case (.calendar, .answered): return .person(calendarsChosen ? "Calendars chosen" : "No calendars chosen")
        case (_, .skipped): return .person("Not now")
        case (.finish, _): return nil
        }
    }
}

/// Where first run starts: nowhere once setup is done, the story before
/// setup begins, then the stored setup question.
public enum FirstRun: Equatable, Sendable {
    case done
    case story
    case setup(SetupStep)

    public init(_ onboarding: Onboarding) {
        if onboarding.completed { self = .done }
        else if let stored = onboarding.setupStep { self = .setup(SetupStep(stored: stored)) }
        else { self = .story }
    }
}

/// First-run copy. Health access is never described as granted.
public enum SetupCopy {
    public struct Scene: Equatable, Sendable, Identifiable {
        public var id: Int
        public var daypart: Welcome.Daypart
        public var eyebrow: String
        public var title: String
        public var body: String
    }

    public static let scenes = [
        Scene(id: 0, daypart: .morning, eyebrow: "Dawn",
              title: "Your day begins with the night before.",
              body: "Record how you slept, from Apple Health or by hand."),
        Scene(id: 1, daypart: .afternoon, eyebrow: "Midday light",
              title: "Caffeine rises and fades through the day.",
              body: "Log a drink in a tap. Aurora models its effect and shows an estimate, never a target."),
        Scene(id: 2, daypart: .evening, eyebrow: "Dusk",
              title: "Your rhythm, in your own sky.",
              body: "Sleep, caffeine and alertness together. Your records stay on this device, with no Aurora account."),
    ]

    public static func question(_ step: SetupStep, modelAvailable: Bool) -> String {
        switch step {
        case .name: "Hi, I’m Aurora. What should I call you?"
        case .sleepTarget: "How much sleep do you aim for on a typical night? It’s your own reference, not a rule."
        case .health: "Apple Health is optional. Each choice below asks Health for that permission alone."
        case .calendar: "I can read calendars you choose to mention what’s coming up. Nothing connects unless you choose it, and I change an event only after you approve a preview."
        case .finish:
            modelAvailable
                ? "You’re set. Ask me about your sleep, caffeine or energy, or use the quick actions."
                : "You’re set. Apple’s local model isn’t available on this device, so start with the quick actions; they work without it."
        }
    }

    /// What the person chose for Health, in the transcript.
    public static func healthAnswer(_ choices: HealthChoices, healthAvailable: Bool) -> String {
        guard healthAvailable else { return "Not available on this device" }
        let on = [HealthChoice.readSleep, .readCaffeine, .writeCaffeine].filter { choices[$0] }.map(\.title)
        return on.isEmpty ? "Not now" : "Requested: " + on.joined(separator: ", ")
    }

    /// The line under the Health choices. Finding nothing proves nothing,
    /// and a declined sheet isn't reported as access.
    public static func healthNote(_ choices: HealthChoices, healthAvailable: Bool, permission: HealthPermissionStatus, demoMode: Bool) -> String {
        if !healthAvailable { return "Apple Health isn’t available on this device. You can log sleep and caffeine yourself." }
        if demoMode { return "Sample Data is on. Turn it off to use Apple Health." }
        if !choices.readSleep && permission == .denied {
            return "The sleep request didn’t finish. You can try again anytime from Apple Health settings."
        }
        if choices.readSleep || choices.readCaffeine {
            return HealthChoice.readSleep.requestedNote
        }
        return "Nothing is shared until you turn a choice on. You can change these anytime in Apple Health settings."
    }

    public static let sampleNote = "Example records, labeled Sample Data everywhere and kept apart from yours. Clear them anytime from Sleep trends in Settings."
}
