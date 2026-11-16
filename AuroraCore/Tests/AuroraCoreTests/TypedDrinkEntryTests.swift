import Foundation
import Testing
@testable import AuroraCore

/// AI-off typed drink entry (CPO, Nov 16): simple typed entries open a filled
/// confirm card; anything unreadable gets a plain message and the manual
/// card. The parser never saves; it says where every number came from.
@Suite struct TypedDrinkEntryTests {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    var clock: LocalClock { LocalClock(timeZone: la) }
    typealias T = TypedDrinkEntry

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Millis {
        guard case .exact(let ms) = CutoffScenario.resolve(.init(year: y, month: m, day: d, hour: h, minute: mi), in: la) else {
            Issue.record("not exact"); return 0
        }
        return ms
    }
    var now: Millis { at(2026, 11, 16, 14) }
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }

    private func entry(_ text: String, now: Millis? = nil) throws -> T.Entry {
        let result = T.parse(text, db: db, now: now ?? self.now, clock: clock)
        guard case .entry(let entry) = result else {
            Issue.record("\(text): \(String(describing: result))")
            throw CancellationError()
        }
        return entry
    }
    private func unreadable(_ text: String) -> String? {
        if case .unreadable(let message) = T.parse(text, db: db, now: now, clock: clock) { return message }
        return nil
    }

    // MARK: Quick Add default (CPO ruling 1)

    @Test func bareCoffeeUsesTheQuickAddDefaultAndSaysSo() throws {
        let e = try entry("coffee")
        #expect(e.draft.mg == "95" && e.draft.source == "Drip" && e.draft.timestamp == now && !e.timeStated)
        #expect(e.amountSource == .quickAddDefault(presetID: "drip", serving: "8 fl oz"))
        #expect(e.provenance == "Quick Add Default · 8 fl oz")
    }

    /// The Drip default is backed by a generic USDA record: SR Legacy 171890,
    /// 1 cup (8 fl oz) = 95 mg. Espresso and Energy defaults are not.
    @Test func onlyTheDripDefaultIsBackedByAGenericUSDARecord() throws {
        let drip = try #require(T.presetServings["drip"])
        let recordID = try #require(drip.usdaEntryID)
        let record = try #require(db.entry(id: recordID))
        #expect(record.publishedServingsOnly == false)
        #expect(record.servings.first { $0.label == "1 cup (8 fl oz)" }?.mg == 95)
        #expect(CaffeinePreset.all.first { $0.id == "drip" }?.mg == 95)
        #expect(T.presetServings["espresso"]?.usdaEntryID == nil && T.presetServings["energy"]?.usdaEntryID == nil)
    }

    @Test func aSizeEqualToTheDefaultIsTheChipValueWithNoLookup() throws {
        let e = try entry("8oz coffee")
        #expect(e.draft.mg == "95" && e.amountSource == .chipSize(presetID: "drip"))
        #expect(e.provenance == "Quick Add · Drip · 8 fl oz")
        let energy = try entry("16 oz energy drink")
        #expect(energy.draft.mg == "160" && energy.amountSource == .chipSize(presetID: "energy"))
    }

    @Test func aDifferentSizeScalesOnlyAUSDABackedDefault() throws {
        let e = try entry("12oz coffee")
        let record = try #require(db.entry(id: "fdc:171890"))
        let volume = try #require(Volume.parse("12oz").first)
        let mg = try #require(db.mg(for: record, volume: volume))
        #expect(mg == 142)
        #expect(e.draft.mg == "142" && e.draft.source == "Coffee")
        #expect(e.amountSource == .scaled(entryID: "fdc:171890", volume: volume.label))
        #expect(e.provenance == "USDA · FDC 171890 · scaled to \(volume.label)")
        // Not backed: the amount stays empty for the person to enter.
        let energy = try entry("12oz energy drink")
        #expect(energy.draft.mg == "" && energy.draft.source == "Energy" && energy.amountSource == .none)
        let double = try entry("double espresso")
        #expect(double.draft.mg == "" && double.draft.source == "Espresso" && double.amountSource == .none)
        #expect(double.provenance == T.enterAmountLine)
    }

    // MARK: Typed amounts

    @Test func theUsersOwnMgIsUsedAsTyped() throws {
        for text in ["espresso 64mg", "64 mg espresso", "I had a 64mg espresso", "log espresso 64 mg"] {
            let e = try entry(text)
            #expect(e.draft.mg == "64" && e.draft.source == "Espresso" && e.amountSource == .typedMg, "\(text)")
            #expect(e.provenance == "Typed amount · mg")
        }
        // A typed amount wins over any default or record, even a size.
        let e = try entry("12oz coffee 150mg")
        #expect(e.draft.mg == "150" && e.amountSource == .typedMg)
    }

    // MARK: Database and brands (CPO ruling 1: brand beats default)

    @Test func aGenericDrinkUsesItsUSDARecordAndScales() throws {
        let tea = try entry("tea")
        #expect(tea.draft.mg == "47" && tea.draft.source == "Tea")
        #expect(tea.amountSource == .database(entryID: "fdc:173227", serving: "1 cup (8 fl oz)"))
        #expect(tea.provenance == "USDA · FDC 173227 · 1 cup (8 fl oz)")
        let latte = try entry("12oz latte")
        let record = try #require(db.entry(id: "fdc:2710386"))
        let volume = try #require(Volume.parse("12oz").first)
        let latteMg = try #require(db.mg(for: record, volume: volume))
        #expect(latte.draft.mg == String(latteMg))
        #expect(latte.amountSource == .scaled(entryID: "fdc:2710386", volume: volume.label) && latte.draft.source == "Latte")
    }

    @Test func aMakersRecordAppliesOnlyAtItsPublishedServing() throws {
        let celsius = try entry("celsius")
        #expect(celsius.draft.mg == "200" && celsius.amountSource == .database(entryID: "mfr:celsius", serving: "1 can (12 fl oz)"))
        #expect(celsius.draft.source == "Celsius Energy Drink")
        #expect(try entry("12 oz celsius").draft.mg == "200")
        let big = try entry("16oz celsius")
        #expect(big.draft.mg == "" && big.amountSource == .none && big.draft.source == "Celsius Energy Drink")
        // A named brand beats the Energy default.
        let energy = try entry("celsius energy drink")
        #expect(energy.draft.mg == "200" && energy.draft.source == "Celsius Energy Drink")
    }

    @Test func aNamedBrandBeatsTheEnergyDefault() throws {
        let e = try entry("red bull")
        // Several Red Bull records: the brand name, and the person enters the amount.
        #expect(e.draft.source == "Red Bull" && e.draft.mg == "" && e.amountSource == .none)
    }

    /// The card's source line names where the number came from while the
    /// amount and drink are unchanged, and reads Manual once edited.
    @Test func sourceLineFollowsEdits() throws {
        let e = try entry("coffee")
        #expect(T.sourceLine(for: e.draft, entry: e) == "Quick Add Default · 8 fl oz · local time")
        var edited = e.draft; edited.mg = "120"
        #expect(T.sourceLine(for: edited, entry: e) == "Manual · local time")
        #expect(T.sourceLine(for: e.draft, entry: nil) == "Manual · local time")
        let empty = try entry("matcha")
        #expect(T.sourceLine(for: empty.draft, entry: empty) == "Manual · local time")
    }

    @Test func excludedBrandsAndMatchaGoToManualEntry() throws {
        for text in ["starbucks latte", "matcha", "ghost energy drink", "12oz matcha"] {
            let e = try entry(text)
            #expect(e.draft.mg == "" && e.amountSource == .none, "\(text)")
            #expect(e.provenance == DrinkPhotoMatcher.unrecordedBrandMessage)
        }
        #expect(try entry("matcha").draft.source == "Matcha")
        #expect(try entry("starbucks latte").draft.source == "Starbucks")
        // The person's own number is manual entry, so it's kept.
        let typed = try entry("starbucks latte 150mg")
        #expect(typed.draft.mg == "150" && typed.amountSource == .typedMg)
    }

    /// A record with no single serving opens with its name and an empty amount.
    @Test func aRecordWithoutOneServingLeavesTheAmountEmpty() throws {
        let e = try entry("kombucha")
        #expect(e.draft.source == "Tea, kombucha" && e.draft.mg == "" && e.amountSource == .none)
    }

    @Test func barcodeDigitsMatchExactly() throws {
        let record = try #require(db.entries.first { $0.gtin != nil && $0.servings.count == 1 })
        let gtin = try #require(record.gtin)
        let e = try entry("log \(gtin)")
        #expect(e.amountSource == .database(entryID: record.id, serving: record.servings[0].label))
        #expect(e.draft.mg == String(record.servings[0].mg))
    }

    // MARK: Time

    @Test func statedTimesAreLocalAndPast() throws {
        let nine = try entry("espresso at 9am")
        #expect(nine.draft.timestamp == at(2026, 11, 16, 9) && nine.timeStated && nine.draft.mg == "60")
        #expect(try entry("coffee 7:30 am").draft.timestamp == at(2026, 11, 16, 7, 30))
        #expect(try entry("coffee yesterday at 8pm").draft.timestamp == at(2026, 11, 15, 20))
        #expect(try entry("I had coffee now").draft.timestamp == now)
        #expect(unreadable("coffee at 9pm") == T.futureTimeMessage)
    }

    @Test func aSkippedDSTTimeIsNotGuessed() {
        let march = at(2026, 3, 8, 12)
        if case .entry = T.parse("coffee at 2:30am", db: db, now: march, clock: clock) { Issue.record("guessed a skipped time") }
    }

    // MARK: Not entries / unreadable

    @Test func questionsAdviceNegationAndOtherRequestsAreNotEntries() {
        for text in ["how much coffee should I drink", "should I have coffee?", "coffee?", "is coffee bad",
                     "I didn't have coffee", "don't log coffee", "log caffeine", "how is my energy",
                     "log sleep", "what can you do", "", "actually tea", "if I had coffee at 5pm"] {
            #expect(T.parse(text, db: db, now: now, clock: clock) == nil, "\(text)")
        }
    }

    @Test func multipleDrinksAndGarbleGetAPlainMessage() {
        for text in ["two coffees", "coffee and tea", "2 espressos", "coffee then tea"] {
            #expect(unreadable(text) == T.oneDrinkMessage, "\(text)")
        }
        #expect(unreadable("coffee blah blah blah") == T.unreadableMessage)
        #expect(unreadable("coffee 5000mg") == T.amountRangeMessage)
        #expect(unreadable("coffee 64mg 80mg") == T.unreadableMessage)
        #expect(unreadable("I had zorbo") == T.unreadableMessage)
        // No drink word, no amount: not a drink entry, other routes decide.
        #expect(T.parse("zorbo", db: db, now: now, clock: clock) == nil)
    }

    @Test func anUnknownDrinkWithTheUsersOwnMgIsKept() throws {
        let e = try entry("zorbo 30mg")
        #expect(e.draft.mg == "30" && e.draft.source == "Zorbo" && e.amountSource == .typedMg)
    }

    @Test func messagesFollowCopyRules() {
        for text in [T.oneDrinkMessage, T.unreadableMessage, T.amountRangeMessage, T.futureTimeMessage, T.enterAmountLine] {
            #expect(CopyRules.violations(in: text).isEmpty)
        }
    }

    @Test func everyDraftValidatesOrLeavesTheAmountEmpty() throws {
        for text in ["coffee", "8oz coffee", "12oz coffee", "espresso 64mg", "tea", "celsius", "espresso at 9am", "12oz latte"] {
            let e = try entry(text)
            #expect(CaffeineLog.validate(e.draft, now: now) == .valid, "\(text)")
        }
    }
}
