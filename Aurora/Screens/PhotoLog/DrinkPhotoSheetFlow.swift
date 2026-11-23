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

    /// A typed drink name, with no photo: the same review card. Writes nothing.
    mutating func reviewTyped(_ lookup: LocalDrinkUnderstanding.DatabaseLookup, db: CaffeineDatabase) {
        let observation = DrinkPhotoObservation(recognizedText: [lookup.phrase])
        card = DrinkPhotoConfirmation(result: DrinkPhotoMatcher.match(observation, in: db), observation: observation, timestamp: lookup.timestamp)
        typed = true
        replacing = lookup.replacing
        saved = false
    }
    /// The saved dose this card corrects, if any.
    private(set) var replacing: String?
    /// Whether the card came from typed text, so the note says so.
    private(set) var typed = false

    /// Card edits (drink, serving, typed amount, manual entry). Never writes.
    mutating func edit(_ change: (inout DrinkPhotoConfirmation) -> Void) {
        guard card != nil else { return }
        change(&card!)
    }

    func draft(db: CaffeineDatabase?, now: Millis) -> CustomDoseDraft? {
        guard let db, let card, var draft = card.draft(db: db, now: now) else { return nil }
        if typed, draft.note.hasPrefix("Photo · ") { draft.note = "Typed · " + draft.note.dropFirst("Photo · ".count) }
        return draft
    }

    enum SaveOutcome: Equatable { case saved, alreadySaved, problem(String) }

    /// The Save button: the only write. The conversation then shows the
    /// standard "Caffeine saved" card with Undo for this entry.
    mutating func save(db: CaffeineDatabase?, assistant: AssistantModel, app: AppModel) -> SaveOutcome {
        guard !saved else { return .alreadySaved }
        app.tick()
        guard let draft = draft(db: db, now: app.now) else { return .problem("Pick a drink and a size first. Nothing was saved.") }
        let problem = replacing.map { assistant.correctPhotoDose(id: $0, with: draft, app: app) } ?? assistant.savePhotoDose(draft, app: app)
        if let problem { return .problem(problem) }
        saved = true
        return .saved
    }

    /// Cancel or dismiss: drops the card. Writes nothing.
    mutating func close() { card = nil; typed = false; replacing = nil }
}
