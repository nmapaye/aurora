import Foundation
import Testing
@testable import AuroraCore

@Suite struct DrinkPhotoLoggingTests {
    let now: Millis = 1_800_000_000_000
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }

    @Test func bundledDatabaseLoadsWithAttributionAndReproducibleServings() throws {
        let db = try #require(CaffeineDatabase.bundled)
        #expect(db.schema == 1 && !db.version.isEmpty)
        #expect(db.entries.count >= 400)
        #expect(Set(db.sources.map(\.id)) == ["fndds-2021-2023", "sr-legacy-2018", "branded-2026-10"])
        for source in db.sources { #expect(source.license.contains("CC0") && source.url.hasPrefix("https://fdc.nal.usda.gov")) }
        for entry in db.entries {
            #expect(db.source(for: entry) != nil)
            for serving in entry.servings {
                #expect(serving.mg == Int((entry.per100 * serving.amount / 100).rounded()))
            }
        }
    }

    @Test func tamperedDatabaseIsRejectedNotUsed() throws {
        let good = """
        {"schema":1,"version":"t","notice":"","sources":[{"id":"s","name":"S","release":"r","license":"CC0","url":"https://fdc.nal.usda.gov/","citation":"c"}],
         "entries":[{"id":"fdc:1","fdcId":1,"source":"s","name":"Coffee, brewed","category":"coffee","per100":40,"basis":"g","servings":[{"label":"1 cup","amount":240,"unit":"g","mg":96}]}]}
        """
        #expect(try CaffeineDatabase.load(from: Data(good.utf8)).entries.count == 1)
        let wrongMg = good.replacingOccurrences(of: "\"mg\":96", with: "\"mg\":120")
        #expect(throws: CaffeineDatabase.LoadError.self) { try CaffeineDatabase.load(from: Data(wrongMg.utf8)) }
        let unknownSource = good.replacingOccurrences(of: "\"source\":\"s\"", with: "\"source\":\"x\"")
        #expect(throws: CaffeineDatabase.LoadError.self) { try CaffeineDatabase.load(from: Data(unknownSource.utf8)) }
        let schema2 = good.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2")
        #expect(throws: CaffeineDatabase.LoadError.self) { try CaffeineDatabase.load(from: Data(schema2.utf8)) }
    }

    @Test func labelVolumesParseCommonPrints() {
        let both = Volume.parse("NET 12 FL OZ (355 mL)")
        #expect(both.count == 1 && abs(both[0].milliliters - 354.88) < 0.1)
        #expect(Volume.parse("16.9 fl. oz").first.map { abs($0.milliliters - 499.8) < 0.2 } == true)
        #expect(Volume.parse("250ml").first?.milliliters == 250)
        #expect(Volume.parse("1 L").first?.milliliters == 1000)
        #expect(Volume.parse("8,4 FL OZ").first.map { abs($0.milliliters - 248.4) < 0.2 } == true)
        // Nutrition-panel lines and non-volumes are not container sizes.
        #expect(Volume.parse("Caffeine 80 mg · Sodium 105mg · 2 g sugars").isEmpty)
        #expect(Volume.parse("5 ml").isEmpty && Volume.parse("9000 ml").isEmpty)
        #expect(Volume.parse("ORIGINAL 12oz").first.map { abs($0.milliliters - 354.88) < 0.1 } == true)
    }

    @Test func barcodeIsAnExactMatchAcrossUpcAndEanForms() throws {
        let entry = try #require(db.entries.first { $0.gtin != nil })
        let gtin = try #require(entry.gtin)
        let stripped = String(gtin.drop { $0 == "0" })
        #expect(db.entry(gtin: "0" + stripped)?.id == entry.id)
        #expect(db.entry(gtin: stripped)?.id == entry.id)
        guard case .candidates(let list, let confident) = DrinkPhotoMatcher.match(.init(barcodes: [stripped]), in: db) else {
            Issue.record("barcode did not match"); return
        }
        #expect(confident && list.count == 1 && list[0].reason == .barcode && list[0].entry.id == entry.id)
        #expect(db.entry(gtin: "123") == nil)
    }

    @Test func labelTextFindsTheBrandedDrinkAndSizeComesFromLabelOnly() throws {
        let observation = DrinkPhotoObservation(recognizedText: ["Red Bull", "ENERGY DRINK", "8.4 FL OZ (250 mL)"])
        guard case .candidates(let list, _) = DrinkPhotoMatcher.match(observation, in: db) else {
            Issue.record("no candidates"); return
        }
        #expect(list.first.map { $0.entry.name.localizedCaseInsensitiveContains("red bull") } == true)
        var card = DrinkPhotoConfirmation(result: .candidates(list, confident: false), observation: observation, timestamp: now - 60_000)
        // Never preselected without confidence: the person picks.
        #expect(card.entry == nil && card.draft(db: db, now: now) == nil)
        #expect(card.clarification(db: db) == "Which drink is this? Pick the closest match.")
        let fndds = try #require(list.first { $0.entry.source == "fndds-2021-2023" && $0.entry.gramsPerFlOz != nil }?.entry)
        card.select(fndds)
        let amount = try #require(card.amount(db: db))
        #expect(amount.mg == db.mg(for: fndds, volume: observation.labelVolumes[0]))
        #expect(amount.provenance.contains("FDC \(fndds.fdcId)") && amount.provenance.contains("from label"))
        let draft = try #require(card.draft(db: db, now: now))
        #expect(draft.mg == String(amount.mg) && draft.note.hasPrefix("Photo · USDA FoodData Central"))
    }

    @Test func modelWordsSearchButItsNumbersNeverBecomeSizesOrAmounts() throws {
        let observation = DrinkPhotoObservation(modelDrink: "espresso 400 mg 20 fl oz", modelBrand: "")
        #expect(observation.labelVolumes.isEmpty)
        guard case .candidates(let list, _) = DrinkPhotoMatcher.match(observation, in: db) else { Issue.record("no match"); return }
        let espresso = try #require(list.first { $0.entry.name == "Coffee, espresso" }?.entry)
        var card = DrinkPhotoConfirmation(result: .candidates(list, confident: false), observation: observation, timestamp: now)
        card.select(espresso)
        #expect(card.serving == nil)
        #expect(card.clarification(db: db) == "What size was it? Pick a serving.")
        #expect(card.draft(db: db, now: now) == nil)
        card.choose(.listed(0))
        let amount = try #require(card.amount(db: db))
        #expect(amount.mg == espresso.servings[0].mg && amount.mg != 400)
    }

    @Test func unrelatedPhotoAsksInsteadOfGuessing() {
        let empty = DrinkPhotoMatcher.match(.init(), in: db)
        guard case .noMatch = empty else { Issue.record("empty observation matched"); return }
        let noise = DrinkPhotoMatcher.match(.init(recognizedText: ["Quarterly budget", "Zebra"], labels: ["table": 0.9]), in: db)
        guard case .noMatch(let message) = noise else { Issue.record("noise matched: \(noise)"); return }
        let card = DrinkPhotoConfirmation(result: noise, observation: .init(), timestamp: now)
        #expect(card.clarification(db: db) == message && card.draft(db: db, now: now) == nil)
    }

    @Test func ocrTypoStillMatchesAtADiscount() {
        #expect(DrinkPhotoMatcher.editDistanceAtMostOne("rockstar", "rockstr"))
        #expect(DrinkPhotoMatcher.editDistanceAtMostOne("monster", "monstor"))
        #expect(!DrinkPhotoMatcher.editDistanceAtMostOne("monster", "master"))
        let result = DrinkPhotoMatcher.match(.init(recognizedText: ["ROCKSTR", "energy"]), in: db)
        guard case .candidates(let list, _) = result else { Issue.record("typo missed"); return }
        #expect(list.contains { $0.entry.name.localizedCaseInsensitiveContains("rockstar") })
    }

    @Test func typedAmountIsMarkedEditedAndValidated() throws {
        let entry = try #require(db.entries.first { $0.name == "Coffee, brewed" })
        var card = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 0.9, reason: .text)], confident: true),
                                          observation: .init(), timestamp: now)
        #expect(card.entry?.id == entry.id)
        card.choose(.listed(0))
        card.type(mg: "2000")
        #expect(card.amount(db: db) == nil && card.draft(db: db, now: now) == nil)
        card.type(mg: "85")
        let amount = try #require(card.amount(db: db))
        #expect(amount.edited && amount.mg == 85 && amount.provenance.hasPrefix("Typed by you (database: "))
        #expect(card.draft(db: db, now: now)?.mg == "85")
        // Changing the drink drops the typed number.
        card.select(entry)
        #expect(card.typedMg == nil)
    }

    @Test func futureTimeAndAutosaveAreRefused() throws {
        #expect(!DrinkPhotoConfirmation.autosaveEnabled)
        let entry = try #require(db.entries.first { $0.name == "Coffee, brewed" })
        var card = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                          observation: .init(), timestamp: now + 3_600_000)
        card.choose(.listed(0))
        #expect(card.draft(db: db, now: now) == nil)
        card.timestamp = now
        #expect(card.draft(db: db, now: now) != nil)
    }

    @Test func gramRecordWithoutFlOzWeightNeverConvertsALabelVolume() throws {
        let entry = try #require(db.entries.first { $0.basis == "g" && $0.gramsPerFlOz == nil && !$0.servings.isEmpty })
        #expect(db.mg(for: entry, volume: Volume(milliliters: 355, text: "12 oz")) == nil)
        let card = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                          observation: .init(recognizedText: ["12 oz"]), timestamp: now)
        #expect(card.usableLabelVolumes.isEmpty)
    }
}
