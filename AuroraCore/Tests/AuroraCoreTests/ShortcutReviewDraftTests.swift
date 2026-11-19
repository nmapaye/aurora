import Foundation
import Testing
@testable import AuroraCore

/// The Log Drink shortcut opens the review card prefilled; it never saves.
@Suite struct ShortcutReviewDraftTests {
    let now: Millis = 1_800_000_000_000

    @Test func logDrinkRequestCarriesTheChosenDrinkToTheReview() {
        var handoff = CaffeineReviewShortcut()
        handoff.request(drink: .espresso)
        #expect(handoff.requested && handoff.drink == .espresso)
        let opened = handoff.consume(ready: true, hasOpenReview: false)
        #expect(opened)
        #expect(handoff.drink == .espresso && !handoff.requested)
        // A plain Review Drink request clears any earlier drink.
        handoff.request()
        #expect(handoff.drink == nil)
        handoff.request(drink: .drip); handoff.cancel()
        #expect(handoff.drink == nil && !handoff.requested)
    }

    @Test func presetPrefillsTheReviewAtItsListedAmount() {
        let draft = LogDrinkShortcut.reviewDraft(.espresso, doses: [], now: now)
        #expect(draft.mg == "60" && draft.source == "Espresso" && draft.timestamp == now)
    }

    @Test func usualPrefillsOnlyFromRecordsAndOtherwiseStartsEmpty() {
        let empty = LogDrinkShortcut.reviewDraft(.usual, doses: [], now: now)
        #expect(empty.mg.isEmpty && empty.source.isEmpty)
        let doses = [
            Dose(id: "a", timestamp: now - 2 * dayMs, mg: 95, source: "Drip"),
            Dose(id: "b", timestamp: now - dayMs, mg: 95, source: "Drip"),
        ]
        let usual = LogDrinkShortcut.reviewDraft(.usual, doses: doses, now: now)
        #expect(usual.mg == "95" && usual.source == "Drip")
    }
}
