import Foundation
import Testing
@testable import AuroraCore

/// Nov 10 feedback on #88: a misread label size is never preselected; a drink
/// the database doesn't have says so and falls back to typing it in; and the
/// brands Nathan named are in the bundled database from their makers, or say Not in Database.
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
        // A USDA Branded label record with one listed bottle: that bottle's size
        // on the photo selects the listed serving; a different size is Not in
        // Database (one exact product at one serving, never scaled).
        let bottle = try #require(db.entries.first { $0.source == "branded-2026-10" && $0.servings[0].amount >= 300 })
        let wrong = card(bottle, label: "\(Int(bottle.servings[0].amount / 2)) mL")
        #expect(wrong.labelVolumes.count == 1 && wrong.serving == nil && wrong.isNotInDatabase)
        let right = card(bottle, label: "\(Int(bottle.servings[0].amount)) mL")
        #expect(right.serving == .listed(0) && right.amount(db: db)?.mg == bottle.servings[0].mg)
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

    /// The brands named in feedback. USDA FoodData Central (CC0) has caffeine
    /// for none of them as drinks, so each value is copied from the maker's
    /// own website or label (page, date, serving and quote in
    /// docs/caffeine-brands-provenance.json; merged by
    /// scripts/merge-manufacturer-caffeine.py). A maker page without an explicit
    /// mg value for that exact serving means no record (CPO, Nov 10: one
    /// published number for one product and serving, or nothing): Starbucks (a
    /// range), Ghost Energy (no value for the can), Dr Pepper (41 and 43 mg) and
    /// 5-hour Energy (200 and 230 mg on Regular Strength pages) show Not in
    /// Database, and matcha is manual entry only.
    static let manufacturerRecords: [(brand: String, id: String, mg: Int, mL: Double, serving: String, url: String)] = [
        ("Celsius", "mfr:celsius", 200, 355, "1 can (12 fl oz)", "https://www.celsius.com/essential-facts/"),
        ("Bang", "mfr:bang", 300, 473, "1 can (16 fl oz)", "https://www.bangenergy.com/en-us/products/purple-haze/"),
        ("Prime", "mfr:prime", 200, 355, "1 can (12 fl oz)", "https://drinkprime-plmmtsmqhvn.gorgias.help/en-US/does-prime-energy-contain-caffeine-565506"),
        ("Alani Nu", "mfr:alani-nu", 200, 355, "1 can (12 fl oz)", "https://www.alaninu.com/products/energy-drink-cherry-twist"),
        ("C4", "mfr:c4-performance-energy", 200, 473, "1 can (16 fl oz)", "https://cellucor.com/products/c4-original-carbonated"),
    ]

    @Test func namedBrandsComeFromTheirMaker() throws {
        let source = try #require(db.sources.first { $0.id == "manufacturer" })
        #expect(source.name == "Manufacturer" && source.shortName == "Manufacturer")
        for item in Self.manufacturerRecords {
            let entry = try #require(db.entry(id: item.id), "\(item.brand) missing")
            #expect(entry.displayName.localizedCaseInsensitiveContains(item.brand))
            #expect(entry.source == "manufacturer" && entry.basis == "mL" && entry.fdcId == nil)
            #expect(entry.url == item.url && entry.retrieved == "2026-11-10")
            #expect(entry.servings.count == 1, "\(item.brand)")
            #expect(entry.servings[0].mg == item.mg && entry.servings[0].amount == item.mL && entry.servings[0].label == item.serving, "\(item.brand)")
            // The (i) credit names the maker's page and links only to it.
            let credit = try #require(db.credit(for: entry))
            #expect(credit.title == "Caffeine Source" && credit.links == [.init(title: "View Source Page", url: item.url)])
            #expect(credit.lines == ["The caffeine amount for this drink is from its maker’s own website or label.", "Retrieved Nov 10, 2026."])
        }
        #expect(db.entries.filter { $0.source == "manufacturer" }.count == Self.manufacturerRecords.count)
        // Generic USDA stand-ins are still there, shown only if picked.
        #expect(db.entries.contains { $0.name == "Soft drink, pepper type" })
        #expect(db.entries.contains { $0.name == "Coffee, brewed" })
        // A photo of the label offers that brand's record; the person still confirms.
        for (text, id) in [("CELSIUS", "mfr:celsius"), ("BANG ENERGY", "mfr:bang"), ("PRIME ENERGY", "mfr:prime"), ("ALANI NU ENERGY", "mfr:alani-nu"),
                           ("C4 ENERGY", "mfr:c4-performance-energy")] {
            guard case .candidates(let list, _) = DrinkPhotoMatcher.match(.init(recognizedText: [text]), in: db) else {
                Issue.record("no candidates for \(text)"); continue
            }
            #expect(list.contains { $0.id == id }, "\(text)")
        }
        // The amount's provenance names the page; the card shows source and serving only.
        let celsius = try #require(db.entry(id: "mfr:celsius"))
        let card = DrinkPhotoConfirmation(result: .candidates([.init(entry: celsius, score: 1, reason: .text)], confident: true),
                                          observation: .init(recognizedText: ["CELSIUS", "12 FL OZ (355 mL)"]), timestamp: now)
        let amount = try #require(card.amount(db: db))
        #expect(amount.mg == 200 && !amount.edited)
        #expect(amount.provenance.hasPrefix("Manufacturer · celsius.com/essential-facts/ · "))
        // The label shows the published serving, so that serving is used, not a label conversion.
        #expect(card.serving == .listed(0) && amount.summary == "Manufacturer · 1 Can (12 fl oz)")
        let listed = DrinkPhotoConfirmation(result: .candidates([.init(entry: celsius, score: 1, reason: .text)], confident: true),
                                            observation: .init(recognizedText: ["CELSIUS"]), timestamp: now)
        #expect(try #require(listed.amount(db: db)).summary == "Manufacturer · 1 Can (12 fl oz)")
        let info = try #require(listed.sourceInfo(db: db))
        #expect(info.lines.first == "Source: Manufacturer · celsius.com/essential-facts/ · 1 can (12 fl oz)")
        #expect(info.lines.contains("Retrieved Nov 10, 2026.") && info.links.map(\.url) == ["https://www.celsius.com/essential-facts/"])
        let draft = try #require(listed.draft(db: db, now: now))
        #expect(draft.mg == "200" && draft.note == "Photo · Manufacturer · celsius.com/essential-facts/ · 1 can (12 fl oz)")
        // Each listed serving reads back in title case on the card.
        for item in Self.manufacturerRecords {
            let entry = try #require(db.entry(id: item.id))
            let c = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                           observation: .init(), timestamp: now)
            let a = try #require(c.amount(db: db), "\(item.brand)")
            #expect(a.mg == item.mg && a.summary == "Manufacturer · " + DrinkPhotoConfirmation.titleCase(item.serving))
        }
    }

    /// Prime publishes 200 mg for the 12 oz can only. A 16 oz can in the
    /// photo, or a 16 oz size picked, never becomes 200 x 473 / 355: the card
    /// falls back to Not in Database and the person types the amount.
    @Test func primeAt16OzFallsBackToManualEntry() throws {
        let prime = try #require(db.entry(id: "mfr:prime"))
        let sixteen = try #require(Volume.parse("16 FL OZ (473 mL)").first)
        #expect(db.mg(for: prime, volume: sixteen) == nil)
        let photo = DrinkPhotoObservation(recognizedText: ["PRIME ENERGY", "16 FL OZ (473 mL)"])
        let match = DrinkPhotoMatcher.match(photo, in: db)
        guard case .candidates(let list, _) = match else { Issue.record("no candidates"); return }
        #expect(list.contains { $0.id == "mfr:prime" })
        // Confident match on the Prime record, 16 oz on the label.
        var card = DrinkPhotoConfirmation(result: .candidates([.init(entry: prime, score: 1, reason: .text)], confident: true),
                                          observation: photo, timestamp: now)
        #expect(card.isNotInDatabase && card.entry == nil && card.serving == nil)
        #expect(card.manualName == "" && card.typedMg == "" && card.amount(db: db) == nil && card.draft(db: db, now: now) == nil)
        card.name("Prime Energy 16 oz"); card.type(mg: "300")
        #expect(card.amount(db: db)?.summary == "Typed by You" && card.draft(db: db, now: now)?.note == "Photo · Typed by you · not in Aurora’s database")
        // Picking Prime again from the list with that photo does the same.
        card.leaveManualEntry(); card.select(prime)
        #expect(card.isNotInDatabase && card.entry == nil)
        // No size in the photo: the 12 oz can is offered; choosing a 16 oz label size falls back too.
        var plain = DrinkPhotoConfirmation(result: .candidates([.init(entry: prime, score: 1, reason: .text)], confident: true),
                                           observation: .init(recognizedText: ["PRIME ENERGY"]), timestamp: now)
        #expect(plain.serving == .listed(0) && plain.amount(db: db)?.mg == 200 && plain.usableLabelVolumes.isEmpty)
        plain.choose(.label(sixteen))
        #expect(plain.isNotInDatabase && plain.amount(db: db) == nil)
        // The 12 oz can on the label is the published serving.
        let twelve = DrinkPhotoConfirmation(result: .candidates([.init(entry: prime, score: 1, reason: .text)], confident: true),
                                            observation: .init(recognizedText: ["PRIME ENERGY", "12 FL OZ (355 mL)"]), timestamp: now)
        #expect(twelve.serving == .listed(0) && twelve.amount(db: db)?.mg == 200 && !twelve.isNotInDatabase)
    }

    /// Every maker's record: its number is used only at its recorded serving.
    /// Any other size, read from the label or chosen, is Not in Database and
    /// manual entry; nothing is scaled through per100. USDA records still
    /// convert label sizes as before.
    @Test func manufacturerRecordsAreNeverScaledToAnotherSize() throws {
        let makers = db.entries.filter { $0.source == "manufacturer" }
        #expect(makers.count == Self.manufacturerRecords.count)
        for entry in makers {
            let recorded = entry.servings[0]
            let same = Volume(milliliters: recorded.amount, text: "\(Int(recorded.amount)) mL")
            let atSize = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                                observation: .init(recognizedText: [same.text]), timestamp: now)
            #expect(atSize.serving == .listed(0) && atSize.amount(db: db)?.mg == recorded.mg, "\(entry.id)")
            #expect(atSize.amount(db: db)?.summary.contains("From Label") == false)
            for factor in [0.5, 4.0 / 3.0, 0.75, 2.0] {
                let other = Volume(milliliters: (recorded.amount * factor).rounded(), text: "\(Int((recorded.amount * factor).rounded())) mL")
                #expect(db.mg(for: entry, volume: other) == nil, "\(entry.id) scaled")
                let shown = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                                   observation: .init(recognizedText: [other.text]), timestamp: now)
                #expect(shown.isNotInDatabase && shown.entry == nil && shown.amount(db: db) == nil, "\(entry.id) at \(other.text)")
                var picked = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                                    observation: .init(), timestamp: now)
                picked.choose(.label(other))
                #expect(picked.isNotInDatabase && picked.amount(db: db) == nil, "\(entry.id) picked \(other.text)")
            }
            // Two sizes on one photo, one of them not the published serving: no record either.
            let mixed = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                               observation: .init(recognizedText: [same.text, "\(Int(recorded.amount * 2)) mL"]), timestamp: now)
            #expect(mixed.isNotInDatabase, "\(entry.id) mixed")
        }
        // USDA label data keeps converting a label size through its own per-100 value.
        let redBull = try #require(db.entries.first { $0.name == "Energy drink (Red Bull)" })
        #expect(!redBull.publishedServingsOnly && db.mg(for: redBull, volume: Volume(milliliters: 250, text: "250 mL")) != nil)
    }

    /// CPO, Nov 10: a USDA Branded record (source "branded-…") is one exact
    /// product, so its label number holds only at its recorded serving. Any
    /// other size, read from the label or picked, is Not in Database with
    /// empty fields for manual entry; nothing is scaled through per100.
    @Test func usdaBrandedRecordsAreNeverScaledToAnotherSize() throws {
        let branded = db.entries.filter { $0.source == "branded-2026-10" }
        #expect(branded.count == 165 && branded.allSatisfy(\.publishedServingsOnly))
        for entry in branded {
            let recorded = entry.servings[0]
            let same = Volume(milliliters: recorded.amount, text: "\(Int(recorded.amount)) mL")
            let atSize = card(entry, label: same.text)
            #expect(atSize.serving == .listed(0) && atSize.amount(db: db)?.mg == recorded.mg, "\(entry.id)")
            #expect(atSize.usableLabelVolumes.isEmpty && db.mg(for: entry, volume: same) == nil)
            for factor in [0.5, 2.0] {
                let ml = (recorded.amount * factor).rounded()
                let other = Volume(milliliters: ml, text: "\(Int(ml)) mL")
                #expect(db.mg(for: entry, volume: other) == nil, "\(entry.id) scaled")
                let shown = card(entry, label: other.text)
                #expect(shown.isNotInDatabase && shown.entry == nil && shown.amount(db: db) == nil, "\(entry.id) at \(other.text)")
                #expect(shown.manualName == "" && shown.typedMg == "")
                var picked = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                                    observation: .init(), timestamp: now)
                #expect(picked.serving == .listed(0))
                picked.choose(.label(other))
                #expect(picked.isNotInDatabase && picked.amount(db: db) == nil && picked.typedMg == "", "\(entry.id) picked \(other.text)")
            }
        }
        // Barcode match on a Branded can with a different size printed: still Not in Database.
        let can = try #require(branded.first { $0.gtin != nil })
        let scan = DrinkPhotoMatcher.match(.init(recognizedText: ["\(Int(can.servings[0].amount * 2)) mL"], barcodes: [can.gtin!]), in: db)
        let scanned = DrinkPhotoConfirmation(result: scan, observation: .init(recognizedText: ["\(Int(can.servings[0].amount * 2)) mL"], barcodes: [can.gtin!]), timestamp: now)
        #expect(scanned.isNotInDatabase && scanned.amount(db: db) == nil)
    }

    /// Edge case: a Branded record listing no serving has no published
    /// number to use, so it is Not in Database even with no size in the photo.
    @Test func brandedRecordWithoutAServingIsNotInDatabase() throws {
        let json = """
        {"schema":1,"version":"t","notice":"","sources":[{"id":"branded-2026-10","name":"USDA FoodData Central, Global Branded Food Products Database","release":"r","license":"CC0","url":"https://fdc.nal.usda.gov/","citation":"c"}],
         "entries":[{"id":"fdc:9","fdcId":9,"source":"branded-2026-10","name":"TEST COLA","category":"soda","per100":10,"basis":"mL","servings":[]}]}
        """
        let tiny = try CaffeineDatabase.load(from: Data(json.utf8))
        let entry = try #require(tiny.entries.first)
        #expect(entry.publishedServingsOnly)
        for observation in [DrinkPhotoObservation(), DrinkPhotoObservation(recognizedText: ["355 mL"])] {
            var c = DrinkPhotoConfirmation(result: .candidates([.init(entry: entry, score: 1, reason: .text)], confident: true),
                                           observation: observation, timestamp: now)
            #expect(c.isNotInDatabase && c.amount(db: tiny) == nil && tiny.mg(for: entry, volume: Volume(milliliters: 355, text: "355 mL")) == nil)
            c.leaveManualEntry(); c.select(entry)
            #expect(c.isNotInDatabase && c.entry == nil)
        }
    }

    /// Generic USDA foods keep converting: brewed coffee (FNDDS, grams with a
    /// 1 fl oz weight) gives each picked cup its own mg, and a label size
    /// converts through the record's per-100 value.
    @Test func genericUsdaCoffeeStillScales() throws {
        let coffee = try #require(db.entries.first { $0.name == "Coffee, brewed" && $0.source == "fndds-2021-2023" })
        #expect(!coffee.publishedServingsOnly && coffee.basis == "g")
        let perFlOz = try #require(coffee.gramsPerFlOz)
        var c = DrinkPhotoConfirmation(result: .candidates([.init(entry: coffee, score: 1, reason: .text)], confident: true),
                                       observation: .init(recognizedText: ["12 FL OZ", "16 FL OZ"]), timestamp: now)
        #expect(!c.isNotInDatabase && c.usableLabelVolumes.count == 2)
        for volume in c.usableLabelVolumes {
            c.choose(.label(volume))
            let expected = Int((coffee.per100 * volume.milliliters / Volume.mlPerFlOz * perFlOz / 100).rounded())
            #expect(c.amount(db: db)?.mg == expected && c.amount(db: db)?.summary.hasSuffix("From Label") == true)
        }
        let twelve = try #require(db.mg(for: coffee, volume: Volume(milliliters: 12 * Volume.mlPerFlOz, text: "12 fl oz")))
        let sixteen = try #require(db.mg(for: coffee, volume: Volume(milliliters: 16 * Volume.mlPerFlOz, text: "16 fl oz")))
        #expect(sixteen > twelve)
        for (index, serving) in coffee.servings.enumerated() {
            c.choose(.listed(index))
            #expect(c.amount(db: db)?.mg == Int((coffee.per100 * serving.amount / 100).rounded()))
        }
    }

    /// 5-hour Energy: the maker sells Berry as Regular Strength yet its page
    /// shows "230mg of Caffeine" beside "Caffeine (200mg)", so there is no
    /// record and no 5-hour photo, Regular, Extra Strength or Berry, maps to one.
    @Test func fiveHourEnergyHasNoRecord() {
        #expect(!db.entries.contains { ($0.name + " " + ($0.brand ?? "")).localizedCaseInsensitiveContains("5-hour") || $0.id.contains("5-hour") })
        for text in [["5-hour ENERGY"], ["5-hour ENERGY", "EXTRA STRENGTH", "230mg"], ["5-hour ENERGY", "BERRY", "REGULAR STRENGTH", "1.93 FL OZ"]] {
            if case .candidates(let list, _) = DrinkPhotoMatcher.match(.init(recognizedText: text), in: db) {
                #expect(!list.contains { $0.entry.source == "manufacturer" || $0.entry.displayName.localizedCaseInsensitiveContains("5-hour") }, "\(text)")
            }
        }
    }

    /// Starbucks and Ghost Energy have no single mg on a maker page, Dr Pepper
    /// and 5-hour have two, and matcha is manual entry only: no record, so a
    /// photo of one never becomes that brand and the person types the amount.
    @Test func unsourcedBrandsAndMatchaShowNotInDatabase() throws {
        for brand in ["Starbucks", "Ghost", "Matcha", "Dr Pepper", "5-hour"] {
            #expect(!db.entries.contains { ($0.name + " " + ($0.brand ?? "")).localizedCaseInsensitiveContains(brand) }, "\(brand)")
        }
        for text in ["STARBUCKS", "GHOST", "MATCHA"] {
            let result = DrinkPhotoMatcher.match(.init(recognizedText: [text]), in: db)
            var card = DrinkPhotoConfirmation(result: result, observation: .init(recognizedText: [text]), timestamp: now)
            #expect(card.isNotInDatabase, "\(text)")
            #expect(card.amount(db: db) == nil && card.draft(db: db, now: now) == nil)
            card.enterManually(); card.name(text.capitalized)
            #expect(card.typedMg == "" && card.amount(db: db) == nil)
            card.type(mg: "120")
            #expect(card.amount(db: db)?.summary == "Typed by You")
        }
        // Dr Pepper's maker publishes 41 and 43 mg: no record, only the generic USDA pepper-type soda if picked.
        if case .candidates(let list, _) = DrinkPhotoMatcher.match(.init(recognizedText: ["Dr Pepper", "12 FL OZ"]), in: db) {
            #expect(!list.contains { $0.entry.source == "manufacturer" || $0.entry.displayName.localizedCaseInsensitiveContains("Dr Pepper") })
        }
        // Even with "energy" on the can, Ghost never becomes another brand's record.
        if case .candidates(let list, _) = DrinkPhotoMatcher.match(.init(recognizedText: ["GHOST ENERGY"]), in: db) {
            #expect(!list.contains { $0.entry.displayName.localizedCaseInsensitiveContains("Ghost") })
        }
    }

    @Test func usdaCreditIsUnchangedBehindInfo() throws {
        let coffee = try #require(db.entries.first { $0.name == "Coffee, brewed" })
        let credit = try #require(db.credit(for: coffee))
        #expect(credit.title == "Caffeine Source" && credit.links.map(\.title) == ["Visit USDA FoodData Central"])
        #expect(credit.lines[0].contains("CC0"))
        // Short visible line; the FDC id and release are only behind (i).
        var card = DrinkPhotoConfirmation(result: .candidates([.init(entry: coffee, score: 1, reason: .text)], confident: true),
                                          observation: .init(), timestamp: now)
        card.select(coffee)
        card.choose(.listed(try #require(coffee.servings.firstIndex { $0.label == "1 cup (8 fl oz)" })))
        let amount = try #require(card.amount(db: db))
        let fdc = try #require(coffee.fdcId)
        #expect(amount.summary == "USDA · 1 Cup (8 fl oz)" && !amount.summary.contains("FDC"))
        let info = try #require(card.sourceInfo(db: db))
        #expect(info.lines[0] == "Source: " + amount.provenance && info.lines[0].contains("FDC \(fdc)") && info.lines[1].contains("released"))
        // Typed amounts: short line only says who typed it.
        card.enterManually(); card.name("Cold brew"); card.type(mg: "150")
        #expect(card.amount(db: db)?.summary == "Typed by You")
        #expect(card.sourceInfo(db: db)?.lines == ["Source: Typed by you · not in Aurora’s database"] && card.sourceInfo(db: db)?.links == [])
        #expect(DrinkPhotoConfirmation.titleCase("1 can or bottle (12 fl oz)") == "1 Can or Bottle (12 fl oz)")
        #expect(DrinkPhotoConfirmation.titleCase("1 Bottle (507 mL)") == "1 Bottle (507 mL)")
        #expect(DrinkPhotoConfirmation.titleCase("1 shot (1.93 fl oz)") == "1 Shot (1.93 fl oz)")
        #expect(CaffeineDatabase.displayDate("2026-11-10") == "Nov 10, 2026" && CaffeineDatabase.displayDate("x") == "x")
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every manufacturer record matches its provenance record exactly (mg,
    /// serving, page, date) and carries the maker's own words. Reads the
    /// committed provenance file from the source tree; no network.
    @Test func everyManufacturerRecordMatchesItsProvenance() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("docs/caffeine-brands-provenance.json"))
        let provenance = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try #require(provenance["records"] as? [[String: Any]])
        #expect(records.count == Self.manufacturerRecords.count)
        for entry in db.entries where entry.source == "manufacturer" {
            let r = try #require(records.first { $0["id"] as? String == entry.id }, "\(entry.id) has no provenance")
            #expect(r["url"] as? String == entry.url && r["retrievedAt"] as? String == entry.retrieved)
            #expect(r["mg"] as? Int == entry.servings[0].mg && r["servingSize"] as? String == entry.servings[0].label)
            #expect((r["servingMl"] as? NSNumber)?.doubleValue == entry.servings[0].amount && (r["per100mL"] as? NSNumber)?.doubleValue == entry.per100)
            let quotes = try #require(r["quote"] as? [String])
            #expect(!quotes.isEmpty && quotes.contains { $0.contains("\(entry.servings[0].mg)") || $0.contains("\(entry.servings[0].mg) mg") }, "\(entry.id) quote lacks its mg")
            #expect(entry.url?.hasPrefix("https://") == true)
        }
        // Brands with no explicit maker value are listed with a reason, and have no record.
        let missing = try #require(provenance["notInDatabase"] as? [[String: Any]])
        #expect(Set(missing.compactMap { $0["brand"] as? String }) == ["Starbucks", "Ghost Energy", "Matcha", "Dr Pepper", "5-hour Energy"])
        for item in missing { #expect((item["reason"] as? String)?.isEmpty == false) }
    }

    /// No shipped text names the dropped third-party source: not the
    /// database, not any card or (i) string, and not the app's or Core's
    /// Swift sources. (The name is assembled here so this file doesn't contain it.)
    @Test func noUserVisibleStringNamesTheDroppedSource() throws {
        let banned = ["caffeine" + " " + "informer", "caffeine" + "informer"]
        func clean(_ text: String, _ what: String) {
            for word in banned { #expect(!text.localizedCaseInsensitiveContains(word), "\(what)") }
        }
        let json = try String(contentsOf: repoRoot.appendingPathComponent("AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json"), encoding: .utf8)
        clean(json, "caffeine-db.json")
        for entry in db.entries {
            if let credit = db.credit(for: entry) {
                clean(([credit.title] + credit.lines + credit.links.flatMap { [$0.title, $0.url] }).joined(separator: "\n"), entry.id)
            }
        }
        clean(DrinkPhotoConfirmation.notInDatabaseTitle + DrinkPhotoConfirmation.manualEntryLine + CaffeineDatabase.creditTitle, "card strings")
        var files = 0
        for dir in ["Aurora", "AuroraCore/Sources"] {
            let base = repoRoot.appendingPathComponent(dir)
            let walker = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
            for case let url as URL in walker where ["swift", "json", "strings", "plist", "md"].contains(url.pathExtension) {
                clean(try String(contentsOf: url, encoding: .utf8), url.lastPathComponent); files += 1
            }
        }
        #expect(files > 20)
    }

    /// Caffeine printed on a label is never read as the amount: amounts come
    /// only from the database record or from the person.
    @Test func labelCaffeineTextNeverBecomesTheAmount() throws {
        let observation = DrinkPhotoObservation(recognizedText: ["Red Bull", "ENERGY DRINK", "CAFFEINE 300 MG", "80mg caffeine", "8.4 FL OZ (250 mL)"])
        guard case .candidates(let list, _) = DrinkPhotoMatcher.match(observation, in: db) else { Issue.record("no candidates"); return }
        let redBull = try #require(list.first { $0.entry.name == "Energy drink (Red Bull)" }?.entry)
        var card = DrinkPhotoConfirmation(result: .candidates(list, confident: false), observation: observation, timestamp: now)
        card.select(redBull)
        let amount = try #require(card.amount(db: db))
        #expect(amount.mg == db.mg(for: redBull, volume: observation.labelVolumes[0]) && ![300, 80].contains(amount.mg))
        let redBullFDC = try #require(redBull.fdcId)
        #expect(!amount.edited && amount.provenance.contains("FDC \(redBullFDC)"))
        // Not in Database: nothing is filled from the label either.
        card.enterManually(); card.name("Red Bull")
        #expect(card.typedMg == "" && card.amount(db: db) == nil && card.draft(db: db, now: now) == nil)
        #expect(DrinkPhotoConfirmation.manualEntryLine == "Enter the caffeine amount from the label or menu.")
    }
}
