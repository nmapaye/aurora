import Foundation

/// The one switch for which drink entries save at once (CPO, Nov 16).
/// `confirm` (the default, unchanged until Nathan decides): every
/// conversation entry opens the card and saves only on Save. `instant`:
/// only these save at once, with an Undo receipt for exactly that entry:
/// a typed entry whose own text gives the drink and its mg, or the drink
/// and the size of its Quick Add chip; and a repeat-drink "Log It" that is
/// an exact copy (same drink, same mg) of a recorded entry, timed now.
/// Always the card, whatever the switch: an amount from a Quick Add
/// default, a database match, scaling or a model; photos; model-inferred
/// entries; the Log Drink and Review Drink shortcuts. The Log tab's Quick
/// Add chips and manual sheet are outside this switch (instant with Undo).
public enum SavePolicy {
    public enum Setting: String, Codable, Sendable { case confirm, instant }
    public enum Decision: Equatable, Sendable { case confirmCard, instantWithUndo }
    public enum Path: Equatable, Sendable { case photo, modelInferred, logDrinkShortcut, reviewDrinkShortcut }

    public static let defaultSetting: Setting = .confirm

    public static func decide(_ path: Path, setting: Setting) -> Decision { .confirmCard }

    public static func typedEntrySavePolicy(_ entry: TypedDrinkEntry.Entry, setting: Setting) -> Decision {
        guard setting == .instant else { return .confirmCard }
        switch entry.amountSource {
        case .typedMg, .chipSize:
            let named = !entry.draft.source.trimmingCharacters(in: .whitespaces).isEmpty
            return named && CaffeineLog.validate(entry.draft, now: entry.draft.timestamp) == .valid ? .instantWithUndo : .confirmCard
        case .quickAddDefault, .database, .scaled, .none:
            return .confirmCard
        }
    }

    /// `draft` is the card's draft as it stands; it must still be the copy.
    public static func repeatDrinkSavePolicy(_ prompt: RepeatDrinks.Prompt, doses: [Dose], draft: CustomDoseDraft, now: Millis,
                                             setting: Setting) -> Decision {
        guard setting == .instant, let recorded = doses.first(where: { $0.id == prompt.doseID }),
              CaffeineLog.isEditable(recorded), recorded.mg == prompt.mg, recorded.source == prompt.source,
              draft == RepeatDrinks.draft(prompt, now: now), CaffeineLog.validate(draft, now: now) == .valid else { return .confirmCard }
        return .instantWithUndo
    }
}
