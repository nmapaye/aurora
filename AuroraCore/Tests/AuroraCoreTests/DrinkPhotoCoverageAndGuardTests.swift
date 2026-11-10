import Foundation
import Testing
@testable import AuroraCore

/// Nov 10 feedback on #88: a misread label size is never preselected; a drink
/// the database doesn't have says so and falls back to typing it in; and the
/// brands Nathan named are checked against the bundled database.
@Suite struct DrinkPhotoCoverageAndGuardTests {
    let now: Millis = 1_800_000_000_000
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }

    private func card(_ entry: CaffeineDatabase.Entry, label: String) -> DrinkPhotoConfirmation {
        DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                               observation: .init(recognizedText: [label]), timestamp: now)
    }

    @Test func misreadLabelVolumeIsNeverPreselected() throws {
        let redBull = try #require(db.entries.first { $0.name == "Energy drink (Red Bull)" })
        // The label size matches one of the record's own cans: preselected.
        let read = card(redBull, label: "8.4 FL OZ (250 mL)")
        #expect(read.serving == .label(read.labelVolumes[0]))
        // OCR read "8.4" as "18.4": no can of that size, so the person picks.
        let misread = card(redBull, label: "18.4 FL OZ")
        #expect(misread.labelVolumes.count == 1 && misread.serving == nil)
        #expect(misread.clarification(db: db) == "What size was it? Pick a serving.")
        #expect(misread.draft(db: db, now: now) == nil)
        // A label record with one listed bottle: a different size read from
        // the photo doesn't preselect either the label or the bottle.
        let bottle = try #require(db.entries.first { $0.basis == "mL" && $0.servings.count == 1 && $0.servings[0].amount >= 300 })
        let wrong = card(bottle, label: "\(Int(bottle.servings[0].amount / 2)) mL")
        #expect(wrong.labelVolumes.count == 1 && wrong.serving == nil)
        let right = card(bottle, label: "\(Int(bottle.servings[0].amount)) mL")
        #expect(right.serving == .label(right.labelVolumes[0]))
        // No size in the photo: the only listed serving is still offered.
        let none = DrinkPhotoConfirmation(result: .candidates([.init(entry: bottle, score: 1, reason: .text)], confident: true),
                                          observation: .init(), timestamp: now)
        #expect(none.serving == .listed(0))
    }

    @Test func notInDatabaseFallsBackToManualEntry() throws {
        let result = DrinkPhotoMatcher.match(.init(recognizedText: ["Quarterly budget", "Zebra"]), in: db)
        var card = DrinkPhotoConfirmation(result: result, observation: .init(), timestamp: now - 60_000)
        #expect(card.isNotInDatabase && DrinkPhotoConfirmation.notInDatabaseTitle == "Not in Database")
        #expect(card.draft(db: db, now: now) == nil)
        card.enterManually()
        #expect(card.clarification(db: db) == "What is the drink called?")
        card.name("  Celsius Sparkling Orange  ")
        #expect(card.clarification(db: db) == "Enter a whole amount between 1 and 1999 mg.")
        card.type(mg: "2000")
        #expect(card.draft(db: db, now: now) == nil)
        card.type(mg: "200")
        let amount = try #require(card.amount(db: db))
        #expect(amount.edited && amount.provenance == "Typed by you · not in Aurora’s database")
        let draft = try #require(card.draft(db: db, now: now))
        #expect(draft.mg == "200" && draft.source == "Celsius Sparkling Orange")
        #expect(draft.note == "Photo · Typed by you · not in Aurora’s database")
        // Picking a database drink afterwards leaves manual entry.
        let coffee = try #require(db.entries.first { $0.name == "Coffee, brewed" })
        card.select(coffee)
        #expect(card.manualName == nil && card.typedMg == nil && !card.isNotInDatabase)
        // A matched card can still switch to typing it in.
        card.enterManually()
        #expect(card.entry == nil && card.isNotInDatabase)
        card.leaveManualEntry()
        #expect(card.manualName == nil && card.typedMg == nil && card.draft(db: db, now: now) == nil)
    }

    /// Which of the brands named in feedback the bundled USDA data has a
    /// brand-specific record for. USDA FoodData Central (CC0) has caffeine
    /// for none of these as drinks: Branded label data reports caffeine for
    /// Alani Nu only as powder "energy sticks", and FNDDS/SR have generic
    /// records only (pepper-type soft drink, brewed and espresso coffee).
    /// Adding any of them needs a licensable source; see FIX-COMMITS-RECEIPT.
    @Test func namedBrandCoverageIsRecorded() {
        let brands = ["Celsius", "Starbucks", "Bang", "Ghost", "Prime", "Alani", "5-hour", "C4", "matcha", "Dr Pepper"]
        let present = brands.filter { brand in
            db.entries.contains { ($0.name + " " + ($0.brand ?? "")).localizedCaseInsensitiveContains(brand) }
        }
        #expect(present == [])
        // Generic stand-ins that are in the database, shown only if picked.
        #expect(db.entries.contains { $0.name == "Soft drink, pepper type" })
        #expect(db.entries.contains { $0.name == "Coffee, brewed" })
        // A photo of an absent brand never becomes that brand.
        for brand in ["Celsius", "Bang", "Ghost", "Prime", "C4"] {
            if case .candidates(let list, _) = DrinkPhotoMatcher.match(.init(recognizedText: [brand.uppercased()]), in: db) {
                #expect(!list.contains { $0.entry.displayName.localizedCaseInsensitiveContains(brand) })
            }
        }
    }
}
