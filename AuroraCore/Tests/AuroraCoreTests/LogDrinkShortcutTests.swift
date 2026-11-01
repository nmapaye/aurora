import Foundation
import Testing
@testable import AuroraCore

struct LogDrinkShortcutTests {
    /// Thu, Oct 8, 2026, noon UTC.
    static let now: Millis = 1_791_460_800_000
    func dose(_ id: String, _ at: Millis, _ mg: Double = 95, _ source: String? = "Drip") -> Dose {
        Dose(id: id, timestamp: at, mg: mg, source: source)
    }
    let time: (Millis) -> String = { _ in "9:00 AM" }

    @Test(arguments: [("espresso", 60.0, "Espresso"), ("drip", 95, "Drip"), ("matcha", 70, "Matcha"), ("energy", 160, "Energy")])
    func presetsUseTheQuickAddAmount(raw: String, mg: Double, label: String) throws {
        let choice = try #require(LogDrinkShortcut.Choice(rawValue: raw))
        let outcome = LogDrinkShortcut.resolve(choice, doses: [], now: Self.now, id: "new")
        #expect(outcome == .log(Dose(id: "new", timestamp: Self.now, mg: mg, source: label)))
        #expect(outcome == .log(CaffeineLog.quickAddDose(try #require(choice.preset), now: Self.now, id: "new")))
    }

    @Test func usualRepeatsTheUsualDrinkAndNeverGuesses() {
        #expect(LogDrinkShortcut.resolve(.usual, doses: [], now: Self.now, id: "new") == .noUsualDrink)
        // One cold brew isn't a usual drink.
        let once = [dose("a", Self.now - dayMs, 200, "Cold Brew")]
        #expect(LogDrinkShortcut.resolve(.usual, doses: once, now: Self.now, id: "new") == .noUsualDrink)
        let twice = once + [dose("b", Self.now - 2 * dayMs, 200, "Cold Brew")]
        #expect(LogDrinkShortcut.resolve(.usual, doses: twice, now: Self.now, id: "new") == .log(dose("new", Self.now, 200, "Cold Brew")))
        // Sample Data never counts.
        let samples = [dose("demo:1", Self.now - dayMs), dose("demo:2", Self.now - 2 * dayMs)]
        #expect(LogDrinkShortcut.resolve(.usual, doses: samples, now: Self.now, id: "new") == .noUsualDrink)
        // Same answer as the assistant's "my usual".
        let usual = AssistantPlanner.usual(twice, now: Self.now)
        #expect(usual?.mg == 200 && usual?.source == "Cold Brew")
    }

    @Test func aRetryWithinTheGuardReturnsTheExistingEntry() {
        let first = dose("a", Self.now)
        let retry = LogDrinkShortcut.resolve(.drip, doses: [first], now: Self.now + LogDrinkShortcut.repeatGuardMs - 1, id: "b")
        #expect(retry == .alreadyLogged(first))
        let later = LogDrinkShortcut.resolve(.drip, doses: [first], now: Self.now + LogDrinkShortcut.repeatGuardMs, id: "b")
        #expect(later == .log(dose("b", Self.now + LogDrinkShortcut.repeatGuardMs)))
        // A different drink is a different drink.
        #expect(LogDrinkShortcut.resolve(.espresso, doses: [first], now: Self.now + 1, id: "b") == .log(dose("b", Self.now + 1, 60, "Espresso")))
        // Health caffeine at the same moment isn't Aurora's entry.
        let health = dose("healthkit:caffeine:x", Self.now)
        #expect(LogDrinkShortcut.resolve(.drip, doses: [health], now: Self.now + 1, id: "b") == .log(dose("b", Self.now + 1)))
    }

    @Test func undoRemovesOnlyTheExactEntry() {
        let saved = dose("a", Self.now)
        let receipt = LogDrinkShortcut.Receipt(saved)
        #expect(LogDrinkShortcut.undoTarget(receipt, doses: [saved]) == saved)
        // Already removed, or corrected to another time: nothing.
        #expect(LogDrinkShortcut.undoTarget(receipt, doses: []) == nil)
        #expect(LogDrinkShortcut.undoTarget(receipt, doses: [dose("a", Self.now - minuteMs)]) == nil)
        // Never Health caffeine or Sample Data, even by id.
        let health = dose("healthkit:caffeine:x", Self.now)
        #expect(LogDrinkShortcut.undoTarget(.init(health), doses: [health]) == nil)
        let sample = dose("demo:x", Self.now)
        #expect(LogDrinkShortcut.undoTarget(.init(sample), doses: [sample]) == nil)
    }

    @Test func undoLastOnlyReachesBackTheWindow() {
        let saved = dose("a", Self.now)
        let receipt = LogDrinkShortcut.Receipt(saved)
        #expect(LogDrinkShortcut.undoLastTarget(nil, doses: [saved], now: Self.now) == nil)
        #expect(LogDrinkShortcut.undoLastTarget(receipt, doses: [saved], now: Self.now + LogDrinkShortcut.undoLastWindowMs) == saved)
        #expect(LogDrinkShortcut.undoLastTarget(receipt, doses: [saved], now: Self.now + LogDrinkShortcut.undoLastWindowMs + 1) == nil)
        // A clock moved backwards doesn't undo.
        #expect(LogDrinkShortcut.undoLastTarget(receipt, doses: [saved], now: Self.now - 1) == nil)
    }

    @Test func copyStatesWhatWasRecorded() {
        let saved = dose("a", Self.now)
        let texts = [
            LogDrinkShortcut.savedText(.log(saved), formatTime: time),
            LogDrinkShortcut.savedText(.alreadyLogged(saved), formatTime: time),
            LogDrinkShortcut.savedText(.noUsualDrink, formatTime: time),
            LogDrinkShortcut.undoneText(saved),
            LogDrinkShortcut.nothingToUndoText,
        ]
        #expect(texts[0] == "Logged Drip, 95 mg at 9:00 AM.")
        #expect(texts[1] == "Drip, 95 mg was logged at 9:00 AM. Nothing new was saved.")
        #expect(texts[3] == "Removed Drip, 95 mg.")
        for text in texts { #expect(CopyRules.violations(in: text).isEmpty, "\(text)") }
    }
}
