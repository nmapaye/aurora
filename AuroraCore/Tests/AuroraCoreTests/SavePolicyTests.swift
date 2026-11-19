import Foundation
import Testing
@testable import AuroraCore

/// The one save switch (CPO, Nov 16). Default confirm until Nathan decides.
/// Set to instant, only a fully specified typed entry and an exact repeat
/// of a recorded entry save at once (with Undo); everything else confirms.
@Suite struct SavePolicyTests {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    var clock: LocalClock { LocalClock(timeZone: la) }
    let now: Millis = 1_794_866_400_000
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }
    typealias P = SavePolicy

    private func typed(_ text: String) throws -> TypedDrinkEntry.Entry {
        guard case .entry(let e) = TypedDrinkEntry.parse(text, db: db, now: now, clock: clock) else {
            Issue.record("\(text)"); throw CancellationError()
        }
        return e
    }

    @Test func defaultIsConfirm() { #expect(P.defaultSetting == .confirm) }

    @Test func confirmSettingNeverSavesAtOnce() throws {
        for text in ["espresso 64mg", "8oz coffee", "coffee", "12oz latte", "tea", "celsius", "matcha"] {
            #expect(P.typedEntrySavePolicy(try typed(text), setting: .confirm) == .confirmCard, "\(text)")
        }
    }

    @Test func instantOnlyForTheUsersOwnMgOrAChipSize() throws {
        for text in ["espresso 64mg", "64 mg espresso at 9am", "8oz coffee", "16oz energy drink", "zorbo 30mg"] {
            #expect(P.typedEntrySavePolicy(try typed(text), setting: .instant) == .instantWithUndo, "\(text)")
        }
        // Default, database match, scaling, empty amount: always the card.
        for text in ["coffee", "espresso", "12oz coffee", "12oz latte", "tea", "celsius", "matcha", "double espresso", "red bull"] {
            #expect(P.typedEntrySavePolicy(try typed(text), setting: .instant) == .confirmCard, "\(text)")
        }
    }

    @Test func otherPathsAlwaysConfirm() {
        for path in [P.Path.photo, .modelInferred, .logDrinkShortcut, .reviewDrinkShortcut] {
            #expect(P.decide(path, setting: .instant) == .confirmCard)
            #expect(P.decide(path, setting: .confirm) == .confirmCard)
        }
    }

    private func dose(_ id: String, _ mg: Double, _ source: String?, at: Millis) -> Dose {
        Dose(id: id, timestamp: at, mg: mg, source: source)
    }
    private func prompt(for dose: Dose, mg: Double? = nil, source: String? = nil) -> RepeatDrinks.Prompt {
        RepeatDrinks.Prompt(doseID: dose.id, source: source ?? dose.source, mg: mg ?? dose.mg, yesterdayAt: dose.timestamp, dueAt: now)
    }

    @Test func repeatDrinkIsInstantOnlyAsAnExactCopyOfARecordedEntry() {
        let yesterday = dose("manual:1", 95, "Drip", at: now - dayMs)
        let doses = [yesterday]
        let exact = prompt(for: yesterday)
        #expect(P.repeatDrinkSavePolicy(exact, doses: doses, draft: RepeatDrinks.draft(exact, now: now), now: now, setting: .instant) == .instantWithUndo)
        #expect(P.repeatDrinkSavePolicy(exact, doses: doses, draft: RepeatDrinks.draft(exact, now: now), now: now, setting: .confirm) == .confirmCard)
        // Changed amount or drink, a removed or sample entry, or not now: the card.
        let changed = prompt(for: yesterday, mg: 120)
        #expect(P.repeatDrinkSavePolicy(changed, doses: doses, draft: RepeatDrinks.draft(changed, now: now), now: now, setting: .instant) == .confirmCard)
        let renamed = prompt(for: yesterday, source: "Tea")
        #expect(P.repeatDrinkSavePolicy(renamed, doses: doses, draft: RepeatDrinks.draft(renamed, now: now), now: now, setting: .instant) == .confirmCard)
        #expect(P.repeatDrinkSavePolicy(exact, doses: [], draft: RepeatDrinks.draft(exact, now: now), now: now, setting: .instant) == .confirmCard)
        let sample = dose("demo:dose:1", 95, "Demo drip", at: now - dayMs)
        let samplePrompt = prompt(for: sample)
        #expect(P.repeatDrinkSavePolicy(samplePrompt, doses: [sample], draft: RepeatDrinks.draft(samplePrompt, now: now), now: now, setting: .instant) == .confirmCard)
        #expect(P.repeatDrinkSavePolicy(exact, doses: doses, draft: RepeatDrinks.draft(exact, now: now - minuteMs), now: now, setting: .instant) == .confirmCard)
        var edited = RepeatDrinks.draft(exact, now: now); edited.mg = "100"
        #expect(P.repeatDrinkSavePolicy(exact, doses: doses, draft: edited, now: now, setting: .instant) == .confirmCard)
    }
}
