import Foundation

/// The rules behind the "Log drink" App Intent (Shortcuts, Siri, Spotlight,
/// the Action button). A log saves at once and can be undone: the intent's
/// result offers Undo for exactly the entry it saved, and "Undo drink"
/// removes the last entry a shortcut saved for a short while after.
///
/// Amounts come only from records Aurora already has: a Quick Add preset at
/// its listed amount (`CaffeinePreset.all`), or the person's usual drink
/// (`AssistantPlanner.usual`: the same source and amount logged at least
/// twice in 30 days). With no usual drink nothing is saved; the shortcut
/// never guesses an amount.
public enum LogDrinkShortcut {
    public enum Choice: String, CaseIterable, Codable, Sendable {
        case usual, espresso, drip, matcha, energy

        /// The Quick Add preset this choice records, nil for `.usual`.
        public var preset: CaffeinePreset? { CaffeinePreset.all.first { $0.id == rawValue } }
    }

    /// An identical request this soon after a shortcut or Quick Add saved the
    /// same drink is a retry or a double press, not a second drink. Longer
    /// than Quick Add's one-second guard because Siri and Shortcuts can
    /// re-run an intent after a slow response.
    public static let repeatGuardMs: Millis = 5000
    /// "Undo drink" without an entry named reaches back this far.
    public static let undoLastWindowMs: Millis = 10 * minuteMs

    public enum Outcome: Equatable, Sendable {
        /// Save this new entry.
        case log(Dose)
        /// The same drink was saved moments ago; nothing new is saved and
        /// this is the entry already there, so Undo still points at it.
        case alreadyLogged(Dose)
        /// `.usual` with no usual drink on record. Nothing is saved.
        case noUsualDrink
    }

    /// What a shortcut saved, kept so Undo can find exactly that entry.
    public struct Receipt: Codable, Equatable, Sendable {
        public var doseID: String
        public var loggedAt: Millis
        public init(doseID: String, loggedAt: Millis) {
            self.doseID = doseID
            self.loggedAt = loggedAt
        }
        public init(_ dose: Dose) { self.init(doseID: dose.id, loggedAt: dose.timestamp) }
    }

    public static func resolve(_ choice: Choice, doses: [Dose], now: Millis, id: String) -> Outcome {
        let dose: Dose
        if let preset = choice.preset {
            dose = CaffeineLog.quickAddDose(preset, now: now, id: id)
        } else {
            guard let prior = AssistantPlanner.usual(doses, now: now), prior.mg > 0 else { return .noUsualDrink }
            dose = Dose(id: id, timestamp: now, mg: prior.mg, source: prior.source)
        }
        if let recent = recentDuplicate(of: dose, in: doses) { return .alreadyLogged(recent) }
        return .log(dose)
    }

    /// The newest editable entry with the same source and amount saved
    /// within `repeatGuardMs` before `dose`.
    static func recentDuplicate(of dose: Dose, in doses: [Dose]) -> Dose? {
        doses.filter {
            CaffeineLog.isEditable($0) && $0.source == dose.source && $0.mg == dose.mg
                && $0.timestamp <= dose.timestamp && dose.timestamp - $0.timestamp < repeatGuardMs
        }.max { $0.timestamp < $1.timestamp }
    }

    /// The entry Undo removes: the one in the receipt, still in Aurora, still
    /// at the time it was saved (an entry corrected since is left alone),
    /// and never Health caffeine or Sample Data.
    public static func undoTarget(_ receipt: Receipt, doses: [Dose]) -> Dose? {
        doses.first { $0.id == receipt.doseID && $0.timestamp == receipt.loggedAt && CaffeineLog.isEditable($0) }
    }

    /// "Undo drink" with no entry named: the last shortcut log, only within
    /// `undoLastWindowMs` of when it was saved. Older entries are deleted in
    /// the Log, where the person can see which one they remove.
    public static func undoLastTarget(_ receipt: Receipt?, doses: [Dose], now: Millis) -> Dose? {
        guard let receipt, now >= receipt.loggedAt, now - receipt.loggedAt <= undoLastWindowMs else { return nil }
        return undoTarget(receipt, doses: doses)
    }

    // MARK: Copy. Describes what was recorded; never an amount to have.

    public static func savedText(_ outcome: Outcome, formatTime: (Millis) -> String) -> String {
        switch outcome {
        case .log(let dose): CaffeineLog.quickAddConfirmation(dose, formatTime: formatTime)
        case .alreadyLogged(let dose): "\(what(dose)) was logged at \(formatTime(dose.timestamp)). Nothing new was saved."
        case .noUsualDrink: noUsualText
        }
    }

    public static let noUsualText = "There’s no usual drink yet. Pick a drink, or open Aurora to log one."
    public static let nothingToUndoText = "Nothing to undo. Entries can be edited or deleted in Aurora’s Log."

    public static func undoneText(_ dose: Dose) -> String { "Removed \(what(dose))." }

    static func what(_ dose: Dose) -> String {
        (dose.source?.isEmpty == false) ? "\(dose.source!), \(numberText(dose.mg)) mg" : "\(numberText(dose.mg)) mg"
    }
}
