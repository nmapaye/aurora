import Foundation
import Testing
@testable import AuroraCore

/// Follow-up chat card (CPO plan §c/§e, Nathan Nov 10): chips for unclear
/// times, a duplicate question with no default, the sleep chip or picker,
/// corrections through the #88 search, and no writes anywhere.
@Suite struct CaffeineAtTimeCardTests {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    var clock: LocalClock { LocalClock(timeZone: la) }
    var text: DateText { .localized(locale: Locale(identifier: "en_US_POSIX"), timeZone: la) }
    var db: CaffeineDatabase { CaffeineDatabase.bundled! }
    typealias Card = CaffeineAtTimeCard

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Millis {
        guard case .exact(let ms) = CutoffScenario.resolve(.init(year: y, month: m, day: d, hour: h, minute: mi), in: la) else {
            Issue.record("not exact"); return 0
        }
        return ms
    }
    var now: Millis { at(2026, 11, 16, 18) }

    private func card(_ question: String, doses: [Dose] = [], sleeps: [SleepSession] = [], now: Millis? = nil) throws -> Card {
        guard case .caffeineAt(let parsed) = CaffeineQuestion.route(question) else {
            Issue.record("\(question) did not route"); throw CancellationError()
        }
        return Card.start(parsed, question: question, db: db, doses: doses, sleeps: sleeps, halfLifeHours: 5, now: now ?? self.now, clock: clock)
    }

    @Test func aTypedDrinkIsEvaluatedNotLoggedWithCodeNumbers() throws {
        let doses = [Dose(id: "d1", timestamp: now - 2 * hourMs, mg: 95)]
        let c = try card("if I drink 126mg now how much at 11pm", doses: doses)
        let result = try #require(c.result)
        let t = at(2026, 11, 16, 23)
        let expected = Caffeine.activeMg(at: t, doses: doses + [Dose(id: "u", timestamp: now, mg: 126)], halfLifeHours: 5)
        #expect(result.rows.map(\.at) == [t])
        #expect(result.rows.first?.valueText == "About \(CaffeineAtTime.displayMg(expected)) mg")
        #expect(c.drink?.asked == .notLogged(.init(mg: 126, at: now, provenance: .typed)))
        let rows = c.rows(text: text)
        #expect(rows.count == 1 && rows[0].label.hasPrefix("At ") && rows[0].label.contains("11:00"))
        let lines = c.lines(text: text, db: db)
        #expect(lines.contains { $0.contains("126 mg") && $0.contains("Not Logged") })
        #expect(lines.contains("Amount: You Entered It"))
        #expect(lines.contains("Includes 1 recorded drink"))
        #expect(c.logDraft == CustomDoseDraft(mg: "126", source: "", timestamp: now, note: ""))
    }

    @Test func aBareHourAsksWithChipsAndNothingIsComputedUntilTapped() throws {
        var c = try card("how much caffeine is active at 9")
        #expect(c.result == nil)
        #expect(c.choices == [.time(.target(0), .clock(hour: 9, minute: 0)), .time(.target(0), .clock(hour: 21, minute: 0))])
        #expect(c.lines(text: text, db: db).contains(Card.pickTimeLine))
        c.choose(.time(.target(0), .clock(hour: 21, minute: 0)), db: db, doses: [], now: now)
        let rows = try #require(c.result?.rows)
        #expect(rows.map(\.at) == [at(2026, 11, 16, 21)])
        #expect(rows.first?.valueText == CaffeineAtTime.noRecordText)
    }

    @Test func intoFivePmAsksForTheDrinkTime() throws {
        var c = try card("126mg impact into 5pm?", now: at(2026, 11, 16, 15))
        #expect(c.result == nil)
        #expect(c.choices.contains(.time(.drink, .clock(hour: 17, minute: 0))) && c.choices.contains(.time(.drink, .now)))
        c.choose(.time(.drink, .now), db: db, doses: [], now: at(2026, 11, 16, 15))
        #expect(c.drink?.at == at(2026, 11, 16, 15))
    }

    @Test func aPastDuplicateAsksWithTwoChipsAndNoDefault() throws {
        let logged = Dose(id: "manual:1", timestamp: at(2026, 11, 16, 17, 20), mg: 126)
        var c = try card("I had 126 mg at 5:27 pm, how much is active at 11 pm?", doses: [logged])
        #expect(c.result == nil && c.drink?.asked == nil)
        #expect(c.choices == [.duplicate(.useLogged), .duplicate(.addAnother)])
        #expect(c.choices.map { c.label(for: $0, text: text, db: db, now: now) } == ["Use Logged Drink", "Add as Another Drink"])
        var other = c
        c.choose(.duplicate(.useLogged), db: db, doses: [logged], now: now)
        #expect(c.drink?.asked == .logged(doseID: "manual:1", mg: 126, at: logged.timestamp))
        #expect(c.logDraft == nil)
        other.choose(.duplicate(.addAnother), db: db, doses: [logged], now: now)
        let mine = try #require(c.result?.rows.first?.totalMg)
        let both = try #require(other.result?.rows.first?.totalMg)
        #expect(both > mine)
    }

    private func night(_ id: String, start: Millis) -> SleepSession {
        SleepSession(id: id, start: start, end: start + 8 * hourMs, type: .sleep)
    }

    @Test func sleepTimeUsesTheRecordedNightsChipOnlyWhenTapped() throws {
        let sleeps = (12...15).map { night("manual:sleep:\($0)", start: at(2026, 11, $0, 23, 10)) }
        var c = try card("How much caffeine will I have tonight?", sleeps: sleeps)
        #expect(c.needsSleepTime && c.result == nil)
        #expect(c.choices == [.sleepChip])
        #expect(c.label(for: .sleepChip, text: text, db: db, now: now).hasSuffix("· 4 Nights"))
        c.choose(.sleepChip, db: db, doses: [], now: now)
        #expect(c.sleepAt == at(2026, 11, 16, 23, 10))
        #expect(c.rows(text: text).first?.label.hasPrefix("At Sleep Time · ") == true)
    }

    @Test func withoutEnoughNightsTheCardAsksWithAPickerNeverTheTarget() throws {
        var c = try card("How much caffeine will I have tonight?", sleeps: [night("manual:sleep:1", start: at(2026, 11, 15, 23))])
        #expect(c.sleepChip == nil && c.choices.isEmpty && c.needsSleepTime)
        c.setSleepTime(hour: 22, minute: 30, doses: [], now: now)
        #expect(c.sleepAt == at(2026, 11, 16, 22, 30))
        #expect(c.result?.rows.count == 1)
    }

    @Test func aNamedDrinkTakesItsDatabaseServing() throws {
        let c = try card("if I have a tea now how much caffeine at 11pm")
        #expect(c.drink?.name == "Tea" && c.drink?.mg == 47)
        #expect(c.drink?.provenance == .database(entryID: "fdc:173227", serving: "1 cup (8 fl oz)"))
        #expect(c.lines(text: text, db: db).contains("Amount: USDA · FDC 173227 · 1 cup (8 fl oz)"))
    }

    @Test func correctingATypedAmountKeepsItAndSaysSo() throws {
        var c = try card("if I drink 126mg now how much at 11pm")
        #expect(Card.correctionPhrase("Actually a caramel latte") == "caramel latte")
        #expect(Card.correctionPhrase("it's tea.") == "tea")
        #expect(Card.correctionPhrase("how much at 11pm") == nil)
        c.correct("caramel latte", db: db, doses: [], now: now, clock: clock)
        #expect(c.drink?.mg == 126 && c.drink?.provenance == .typed)
        #expect(c.note == "Amount kept: 126 mg (you entered it)")
        #expect(c.result != nil)
    }

    @Test func correctingADatabaseAmountReResolvesThroughTheSearch() throws {
        var c = try card("if I have a tea now how much caffeine at 11pm")
        c.correct("latte", db: db, doses: [], now: now, clock: clock)
        let latte = try #require(db.entry(id: "fdc:2710386"))
        let expected = TypedDrinkEntry.recordAmount(latte, volume: nil, db: db).mg.map(Double.init)
        #expect(c.drink?.mg == expected && c.drink?.name == "Latte")
        if case .database(let id, _)? = c.drink?.provenance { #expect(id == "fdc:2710386") } else { Issue.record("not database") }

        // Not one record: up to three candidates plus Enter Amount; no number yet.
        c.correct("caramel latte", db: db, doses: [], now: now, clock: clock)
        #expect(c.drink?.mg == nil && c.needsAmount && c.result == nil)
        #expect(!c.candidateIDs.isEmpty && c.candidateIDs.count <= Card.maxCandidates)
        #expect(c.note == Card.amountLine)
        let pick = try #require(c.candidateIDs.first)
        var picked = c
        picked.choose(.candidate(entryID: pick), db: db, doses: [], now: now)
        #expect(picked.drink?.mg == nil || picked.result != nil)
        let accepted = c.setAmount("80", doses: [], now: now)
        #expect(accepted)
        #expect(c.drink?.mg == 80 && c.drink?.provenance == .typed && c.result != nil)
        let zero = c.setAmount("0", doses: [], now: now)
        let fraction = c.setAmount("12.5", doses: [], now: now)
        #expect(!zero && !fraction)
    }

    @Test func aMakersRecordIsNeverScaled() throws {
        var c = try card("if I have a tea now how much caffeine at 11pm")
        c.correct("16 oz celsius", db: db, doses: [], now: now, clock: clock)
        #expect(c.drink?.mg == nil && c.needsAmount)
        c.correct("celsius", db: db, doses: [], now: now, clock: clock)
        #expect(c.drink?.mg == 200)
    }

    @Test func excludedBrandsAndMatchaGoToManualEntry() throws {
        for phrase in ["matcha", "starbucks latte", "dr pepper"] {
            var c = try card("if I have a tea now how much caffeine at 11pm")
            c.correct(phrase, db: db, doses: [], now: now, clock: clock)
            #expect(c.drink?.mg == nil && c.candidateIDs.isEmpty && c.result == nil, "\(phrase)")
            #expect(c.note == DrinkPhotoMatcher.unrecordedBrandMessage, "\(phrase)")
        }
    }

    @Test func aQuestionWithoutATargetUsesTheNextThreeWholeHours() throws {
        let c = try card("if I drink 126mg now how much at 11pm")
        #expect(c.targets.count == 1)
        var open = c
        open.targetSpecs = []; open.targets = []
        open.resolve(doses: [], now: at(2026, 11, 16, 18, 20))
        #expect(open.targets == [at(2026, 11, 16, 19), at(2026, 11, 16, 20), at(2026, 11, 16, 21)])
    }

    @Test func theCardRoundTripsAsStoredState() throws {
        let c = try card("I had 126 mg at 5:27 pm, how much is active at 11 pm?")
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(Card.self, from: data) == c)
    }

    @Test func copyIsCodeWrittenAndTitleCase() {
        for label in [Card.enterAmountLabel, Card.sleepPickerLabel, CaffeineAtTime.logThisDrinkLabel, CaffeineAtTime.title] {
            let words = label.split(separator: " ")
            #expect(words.allSatisfy { $0.first?.isUppercase == true }, "\(label)")
        }
        #expect(CaffeineAtTime.settingsHalfLifeInfo(5) == "Estimated with your half-life setting (5 h). In one study of 10 healthy young men, half-lives ranged from about 3 to 10 hours. Source: Blanchard J, Sawers SJA. The absolute bioavailability of caffeine in man. Eur J Clin Pharmacol 1983;24:93–98. doi:10.1007/BF00613933. PubMed 6832208.")
        for line in [Card.pickTimeLine, Card.skippedTimeLine, Card.duplicateLine, Card.amountLine, Card.amountKeptLine(126),
                     Card.enterAmountLabel, Card.sleepPickerLabel, CaffeineAtTime.settingsHalfLifeInfo(5)] {
            #expect(CopyRules.violations(in: line).isEmpty, "\(line)")
            for word in ["gardiner", "sleep study", "should", "safe", "recommend", "impact"] {
                #expect(!line.lowercased().contains(word), "\(line)")
            }
        }
    }

    @Test func aSkippedSleepChipAsksForAnotherTime() throws {
        let now = at(2026, 3, 8, 0, 30)
        let sleeps = (4...7).map { night("manual:sleep:\($0)", start: at(2026, 3, $0, 2, 30)) }
        var c = try card("How much caffeine will I have tonight?", sleeps: sleeps, now: now)
        #expect(c.sleepChip?.minuteOfDay == 150)
        c.choose(.sleepChip, db: db, doses: [], now: now)
        #expect(c.sleepAt == nil && c.result == nil && c.needsSleepTime)
        #expect(c.lines(text: text, db: db).contains(Card.skippedSleepLine))
        c.setSleepTime(hour: 23, minute: 0, doses: [], now: now)
        #expect(c.sleepAt == at(2026, 3, 8, 23) && c.result != nil && !c.skipped.contains(.sleep))
    }

    @Test func aRepeatedSleepChipOffersBothInstants() throws {
        let now = at(2026, 11, 1, 0, 30)
        let sleeps = (28...31).map { night("manual:sleep:\($0)", start: at(2026, 10, $0, 1, 30)) }
        var c = try card("How much caffeine will I have tonight?", sleeps: sleeps, now: now)
        #expect(c.sleepChip?.minuteOfDay == 90)
        c.choose(.sleepChip, db: db, doses: [], now: now)
        guard case .repeated(let first, let second) = CutoffScenario.resolve(.init(year: 2026, month: 11, day: 1, hour: 1, minute: 30), in: la) else {
            Issue.record("not repeated"); return
        }
        #expect(c.sleepAt == nil && c.result == nil)
        #expect(c.choices == [.instant(.sleep, first, first: true), .instant(.sleep, second, first: false)])
        #expect(c.lines(text: text, db: db).contains(Card.repeatedTimeLine))
        c.choose(.instant(.sleep, second, first: false), db: db, doses: [], now: now)
        #expect(c.sleepAt == second && c.result?.rows.first?.at == second)
    }
}
