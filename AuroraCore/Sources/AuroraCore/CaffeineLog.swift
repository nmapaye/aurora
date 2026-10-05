import Foundation

/// Log states what was recorded and where it came from. It never frames the
/// day's total against a limit, allowance or "remaining" amount, and never
/// suggests how much caffeine to have.
public struct CaffeinePreset: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var mg: Double
    /// SF Symbol name.
    public var symbol: String

    public static let all: [CaffeinePreset] = [
        CaffeinePreset(id: "espresso", label: "Espresso", mg: 60, symbol: "cup.and.saucer.fill"),
        CaffeinePreset(id: "drip", label: "Drip", mg: 95, symbol: "cup.and.saucer.fill"),
        CaffeinePreset(id: "matcha", label: "Matcha", mg: 70, symbol: "leaf.fill"),
        CaffeinePreset(id: "energy", label: "Energy", mg: 160, symbol: "bolt.fill"),
    ]
}

public struct CustomDoseDraft: Equatable, Sendable {
    /// The amount as typed.
    public var mg: String
    public var source: String
    public var timestamp: Millis
    public var note: String

    public init(mg: String, source: String, timestamp: Millis, note: String) {
        self.mg = mg
        self.source = source
        self.timestamp = timestamp
        self.note = note
    }
}

public enum DraftValidation: Equatable, Sendable {
    case valid
    case invalid(String)

    public var message: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

public enum CaffeineLog {
    public static let recentLimit = 5
    /// A second quick-add tap this soon after the last is an accidental
    /// double tap, not a second drink.
    public static let quickAddRepeatGuardMs: Millis = 1000
    /// Source chips offered by Custom Entry.
    public static let customSources = ["Espresso", "Drip", "Cold Brew", "Tea", "Matcha", "Other"]

    public static func todayTotal(_ doses: [Dose], now: Millis, clock: LocalClock) -> Double {
        let start = clock.startOfDay(now)
        let end = clock.addingDays(1, to: start)
        return doses.reduce(0) { $0 + (($1.timestamp >= start && $1.timestamp < end) ? $1.mg : 0) }
    }

    public static func newDraft(now: Millis) -> CustomDoseDraft {
        CustomDoseDraft(mg: "80", source: "Drip", timestamp: now, note: "")
    }

    /// `Number(text)` for a typed amount: surrounding whitespace is ignored and
    /// an empty field reads as 0.
    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return Double(trimmed)
    }

    public static func validate(_ draft: CustomDoseDraft, now: Millis) -> DraftValidation {
        guard let mg = parseAmount(draft.mg), mg.isFinite, mg.rounded() == mg, mg >= 1, mg <= 1999 else {
            return .invalid("Amount must be between 1 and 1999 mg.")
        }
        guard draft.timestamp.isFinite, draft.timestamp <= now else {
            return .invalid("Time cannot be in the future.")
        }
        return .valid
    }

    public static func quickAddDose(_ preset: CaffeinePreset, now: Millis, id: String) -> Dose {
        Dose(id: id, timestamp: now, mg: preset.mg, source: preset.label)
    }

    public static func customDose(_ draft: CustomDoseDraft, id: String) -> Dose {
        var dose = patch(from: draft)
        dose.id = id
        return dose
    }

    /// Loads an existing entry into the draft shape Custom Entry uses.
    public static func editDraft(for dose: Dose) -> CustomDoseDraft {
        CustomDoseDraft(mg: numberText(dose.mg), source: dose.source ?? "", timestamp: dose.timestamp, note: dose.note ?? "")
    }

    /// The fields a correction replaces. The id is left empty; the entry
    /// being corrected keeps its own.
    public static func patch(from draft: CustomDoseDraft) -> Dose {
        let source = draft.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Dose(
            id: "",
            timestamp: draft.timestamp,
            mg: parseAmount(draft.mg) ?? 0,
            source: source.isEmpty ? nil : source,
            note: note.isEmpty ? nil : note
        )
    }

    public static func sourceLabel(_ dose: Dose) -> String {
        RecordID.isSample(dose.id) ? "Sample Data" : "Manual"
    }

    /// Sample Data is labeled and read-only. Only entries the user recorded
    /// can be corrected or deleted.
    public static func isEditable(_ dose: Dose) -> Bool {
        !RecordID.isSample(dose.id)
    }

    /// Sample entries all carry the note "Sample data", which only repeats
    /// their label, so display skips it. Any other note is shown as written.
    public static func displayNote(_ dose: Dose) -> String? {
        guard let note = dose.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        if RecordID.isSample(dose.id) && note.lowercased() == "sample data" { return nil }
        return dose.note
    }

    public static func title(_ dose: Dose) -> String {
        if let source = dose.source, !source.isEmpty {
            return "\(numberText(dose.mg)) mg · \(source)"
        }
        return "\(numberText(dose.mg)) mg"
    }

    public static func describe(_ dose: Dose, formatDateTime: (Millis) -> String) -> String {
        let note = displayNote(dose)
        return [
            "\(numberText(dose.mg)) mg",
            dose.source,
            formatDateTime(dose.timestamp),
            isEditable(dose) ? "Manual" : "Sample Data, read-only",
            note.map { "Note: \($0)" },
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    public static func recent(_ doses: [Dose], limit: Int = recentLimit) -> [Dose] {
        Array(
            doses.enumerated()
                .sorted { $0.element.timestamp != $1.element.timestamp ? $0.element.timestamp > $1.element.timestamp : $0.offset < $1.offset }
                .map(\.element)
                .prefix(limit)
        )
    }

    public struct LoggedToday: Equatable, Sendable {
        public var label: String
        public var value: String
        public var source: String?
        public var sample: Bool
        public var detail: String
        public var accessibilityLabel: String
    }

    /// Same total and source wording as Summary's Caffeine Logged signal, so
    /// the two screens never disagree about today.
    public static func loggedToday(_ doses: [Dose], now: Millis, clock: LocalClock, formatTime: (Millis) -> String) -> LoggedToday {
        let signal = SummarySignals.caffeineLogged(doses: doses, now: now, clock: clock, formatTime: formatTime)
        let label = "Logged Today"
        guard signal.status != .empty else {
            let detail = "Nothing logged yet today."
            return LoggedToday(label: label, value: "0 mg", source: nil, sample: false, detail: detail, accessibilityLabel: "\(label), 0 mg, \(detail)")
        }
        let value = signal.value ?? "0 mg"
        return LoggedToday(
            label: label,
            value: value,
            source: signal.source,
            sample: signal.source != "Manual",
            detail: signal.context,
            accessibilityLabel: [label, value, signal.source ?? "", signal.context].joined(separator: ", ")
        )
    }

    public static func acceptsQuickAdd(lastAcceptedAt: Millis?, at: Millis) -> Bool {
        guard let lastAcceptedAt else { return true }
        return at < lastAcceptedAt || at - lastAcceptedAt >= quickAddRepeatGuardMs
    }

    public static func quickAddConfirmation(_ dose: Dose, formatTime: (Millis) -> String) -> String {
        let what = (dose.source?.isEmpty == false) ? "\(dose.source!), \(numberText(dose.mg)) mg" : "\(numberText(dose.mg)) mg"
        return "Logged \(what) at \(formatTime(dose.timestamp))."
    }
}

public enum SummarySignals {
    /// Summary's one route into Log, empty or not.
    public static func caffeineLogged(doses: [Dose], now: Millis, clock: LocalClock, formatTime: (Millis) -> String) -> SignalCardModel {
        let dayStart = clock.startOfDay(now)
        let today = doses.filter { $0.timestamp >= dayStart && $0.timestamp <= now }
        guard let last = today.max(by: { $0.timestamp < $1.timestamp }) else {
            return SignalCardModel(
                id: "caffeine", label: "Caffeine Logged", period: "Today", status: .empty,
                context: "Nothing logged yet today.", destination: "Log Caffeine"
            )
        }
        let total = jsRoundInt(today.reduce(0) { $0 + $1.mg })
        let sampleCount = today.filter { RecordID.isSample($0.id) }.count
        let allSample = sampleCount == today.count
        return SignalCardModel(
            id: "caffeine",
            label: "Caffeine Logged",
            period: "Today",
            source: allSample ? "Sample Data" : (sampleCount > 0 ? "Manual and Sample Data" : "Manual"),
            status: allSample ? .sample : .observed,
            value: "\(total) mg",
            context: "\(today.count) \(today.count == 1 ? "entry" : "entries") · last at \(formatTime(last.timestamp))",
            destination: "Open Log"
        )
    }

    public static func sleep(
        sleeps: [SleepSession],
        targetSleepHours: Double,
        now: Millis,
        clock: LocalClock,
        text: DateText
    ) -> SignalCardModel {
        let lastNight = SleepModel.presentation(
            sessions: sleeps, targetSleepHours: targetSleepHours, range: .week, now: now, clock: clock, text: text
        ).lastNight
        guard let lastNight else {
            return SignalCardModel(
                id: "sleep", label: "Sleep", period: "Last 7 days", status: .empty,
                context: "None recorded in the last 7 days.", destination: "Add Sleep"
            )
        }
        let source = SleepModel.sourceLabel(id: lastNight.session.id)
        let period = formatSignalDay(lastNight.wakeTime, now: now, clock: clock, text: text)
        let span = "\(text.clockTime(lastNight.sleepStart)) – \(text.clockTime(lastNight.wakeTime))"
        return SignalCardModel(
            id: "sleep",
            label: "Sleep",
            period: period,
            source: source,
            status: source == "Sample Data" ? .sample : .observed,
            value: formatHoursMinutes(durationMs: lastNight.durationMs),
            context: period == "Today" || period == "Yesterday" ? span : "Latest night recorded · \(span)",
            destination: "Open Sleep"
        )
    }

    public static func reactionTest(sessions: [VigilanceSession], now: Millis, clock: LocalClock, text: DateText) -> SignalCardModel {
        var latest: VigilanceSession?
        for session in sessions where session.completedAt <= now && (latest == nil || session.completedAt > latest!.completedAt) {
            latest = session
        }
        guard let latest else {
            return SignalCardModel(
                id: "reaction-test", label: "Reaction Test", period: "No test yet", status: .empty,
                context: "A 60-second test of reaction speed.", destination: "Take Reaction Test"
            )
        }
        let sample = RecordID.isSample(latest.id)
        return SignalCardModel(
            id: "reaction-test",
            label: "Reaction Test",
            period: formatSignalDay(latest.completedAt, now: now, clock: clock, text: text),
            source: sample ? "Sample Data" : nil,
            status: sample ? .sample : .observed,
            value: "\(latest.score)",
            context: latest.medianReactionMs.map { "\(latest.rating.rawValue) · \(jsRoundInt($0)) ms median" } ?? latest.rating.rawValue,
            destination: "Take Reaction Test"
        )
    }
}
