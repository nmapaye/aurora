import AuroraCore

/// The photo sheet's review and Save steps, without the view, so a test can
/// drive the sheet's own path: a read photo opens the review card (nothing
/// is written), edits change only the card, Save is the only write and runs
/// once, and Cancel writes nothing. `DrinkPhotoSheet` holds one of these in
/// `@State` and calls it from `begin`, its Save button and Cancel.
@MainActor
struct DrinkPhotoSheetFlow {
    private(set) var card: DrinkPhotoConfirmation?
    /// Set once Save succeeds, so a second tap can't add the drink twice.
    private(set) var saved = false

    var isReviewing: Bool { card != nil }

    /// What the sheet does when the on-device read finishes. Writes nothing.
    mutating func review(_ observation: DrinkPhotoObservation, db: CaffeineDatabase, now: Millis) {
        card = DrinkPhotoConfirmation(result: DrinkPhotoMatcher.match(observation, in: db), observation: observation, timestamp: now)
        saved = false
    }

    /// Card edits (drink, serving, typed amount, manual entry). Never writes.
    mutating func edit(_ change: (inout DrinkPhotoConfirmation) -> Void) {
        guard card != nil else { return }
        change(&card!)
    }

    func draft(db: CaffeineDatabase?, now: Millis) -> CustomDoseDraft? {
        guard let db, let card else { return nil }
        return card.draft(db: db, now: now)
    }

    enum SaveOutcome: Equatable { case saved, alreadySaved, problem(String) }

    /// The Save button: the only write. The conversation then shows the
    /// standard "Caffeine saved" card with Undo for this entry.
    mutating func save(db: CaffeineDatabase?, assistant: AssistantModel, app: AppModel) -> SaveOutcome {
        guard !saved else { return .alreadySaved }
        app.tick()
        guard let draft = draft(db: db, now: app.now) else { return .problem("Pick a drink and a size first. Nothing was saved.") }
        if let problem = assistant.savePhotoDose(draft, app: app) { return .problem(problem) }
        saved = true
        return .saved
    }

    /// Cancel or dismiss: drops the card. Writes nothing.
    mutating func close() { card = nil }
}
