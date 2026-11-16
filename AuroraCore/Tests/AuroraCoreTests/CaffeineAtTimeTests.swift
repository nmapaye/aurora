import Foundation
import Testing
@testable import AuroraCore

/// Caffeine follow-up chat core (slice 1): evaluator, display rounding,
/// sleep-time chip and the deterministic (AI-off) question route.
@Suite struct CaffeineAtTimeTests {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    var clock: LocalClock { LocalClock(timeZone: la) }
    typealias C = CaffeineAtTime
    typealias Q = CaffeineQuestion

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Millis {
        guard case .exact(let ms) = CutoffScenario.resolve(.init(year: y, month: m, day: d, hour: h, minute: mi), in: la) else {
            Issue.record("not exact"); return 0
        }
        return ms
    }

    // MARK: Evaluator

    /// CPO §e-1: 126 mg at 17:27, t½ 5 h → 67.1 / 58.4 / 50.8 / 44.2 mg, card ~65/60/50/45.
    @Test func goldenUnloggedDrink() {
        let now = at(2026, 11, 16, 18, 4)
        let drink = C.UnloggedDrink(mg: 126, at: at(2026, 11, 16, 17, 27), provenance: .typed)
        let targets = [at(2026, 11, 16, 22), at(2026, 11, 16, 23), at(2026, 11, 17, 0), at(2026, 11, 17, 1)]
        let result = C.evaluate(doses: [], unlogged: drink, halfLifeHours: 5, targets: targets, now: now)
        #expect(result.problems.isEmpty)
        let tenths = result.rows.map { ($0.totalMg * 10).rounded() / 10 }
        #expect(tenths == [67.1, 58.4, 50.8, 44.2])
        #expect(result.rows.map(\.displayMg) == [65, 60, 50, 45])
        #expect(result.rows.map(\.valueText) == ["About 65 mg", "About 60 mg", "About 50 mg", "About 45 mg"])
        // Every number is Caffeine.activeMg, nothing else.
        for row in result.rows {
            #expect(row.totalMg == Caffeine.activeMg(at: row.at, doses: [Dose(id: "q", timestamp: drink.at, mg: 126)], halfLifeHours: 5))
            #expect(row.unloggedMg == row.totalMg && row.recordedMg == 0 && row.sampleMg == 0)
        }
    }

    @Test func displayRoundingIsNearestFiveHalfUp() {
        #expect([0.0, 2.4, 2.5, 7.4, 7.5, 62.5, 67.1, 58.4, 50.8, 44.2, 99.99].map(C.displayMg) == [0, 0, 5, 5, 10, 65, 65, 60, 50, 45, 100])
    }

    @Test func underTwoAndAHalfMgShowsLessThanFive() {
        let now = at(2026, 11, 16, 18)
        // 10 mg at 8:00 → 10 · 0.5^(15/5) = 1.25 mg at 23:00: records exist, so not "No record".
        let doses = [Dose(id: "manual:1", timestamp: at(2026, 11, 16, 8), mg: 10)]
        let row = C.evaluate(doses: doses, unlogged: nil, halfLifeHours: 5, targets: [at(2026, 11, 16, 23)], now: now).rows[0]
        #expect(abs(row.totalMg - 1.25) < 1e-9)
        #expect(!row.isNoRecord && row.isBelowDisplay)
        #expect(row.valueText == "Less than 5 mg")
        // 2.5 mg exactly rounds to 5 and shows "About 5 mg".
        let edge = C.evaluate(doses: [Dose(id: "manual:2", timestamp: at(2026, 11, 16, 8), mg: 20)], unlogged: nil, halfLifeHours: 5, targets: [at(2026, 11, 16, 23)], now: now).rows[0]
        #expect(edge.totalMg == 2.5 && edge.valueText == "About 5 mg" && !edge.isBelowDisplay)
        #expect(C.evaluate(doses: [], unlogged: nil, halfLifeHours: 5, targets: [now], now: now).rows[0].valueText == "No record")
    }

    // MARK: Asked drink vs a logged one (never merged silently)

    @Test func pastDrinkMatchingLoggedEntryAsksWithTwoChipsNoDefault() {
        let now = at(2026, 11, 16, 18)
        let logged = Dose(id: "manual:esp", timestamp: at(2026, 11, 16, 15), mg: 64)
        let asked = C.UnloggedDrink(mg: 64, at: at(2026, 11, 16, 15, 20), provenance: .typed)
        guard case .needsChoice(let question) = C.checkAskedDrink(asked, doses: [logged], now: now) else { Issue.record("expected a question"); return }
        #expect(question.options == [.useLogged, .addAnother])
        #expect(question.options.map(\.label) == ["Use Logged Drink", "Add as Another Drink"])
        #expect(question.loggedDoseID == "manual:esp")
        let target = at(2026, 11, 16, 23)

        let useLogged = question.answer(.useLogged)
        #expect(useLogged == .logged(doseID: "manual:esp", mg: 64, at: logged.timestamp))
        #expect(useLogged.label == "Logged")
        let r1 = C.evaluate(doses: [logged], asked: useLogged, halfLifeHours: 5, targets: [target], now: now)
        #expect(r1.drinkLabel == "Logged" && r1.unlogged == nil)
        #expect(r1.rows[0].totalMg == Caffeine.activeMg(at: target, doses: [logged], halfLifeHours: 5))

        let another = question.answer(.addAnother)
        #expect(another == .notLogged(asked) && another.label == "Not Logged")
        let r2 = C.evaluate(doses: [logged], asked: another, halfLifeHours: 5, targets: [target], now: now)
        #expect(r2.drinkLabel == "Not Logged" && r2.unlogged == asked)
        #expect(r2.rows[0].totalMg == Caffeine.activeMg(at: target, doses: [logged, Dose(id: "q", timestamp: asked.at, mg: 64)], halfLifeHours: 5))
    }

    @Test func noMatchAddsDrinkWithoutAQuestion() {
        let now = at(2026, 11, 16, 18)
        let logged = Dose(id: "manual:esp", timestamp: at(2026, 11, 16, 15), mg: 64)
        let cases: [(C.UnloggedDrink, [Dose])] = [
            (.init(mg: 80, at: at(2026, 11, 16, 15, 10), provenance: .typed), [logged]),            // different mg
            (.init(mg: 64, at: at(2026, 11, 16, 15, 31), provenance: .typed), [logged]),            // 31 min apart
            (.init(mg: 64, at: at(2026, 11, 16, 19), provenance: .typed), [Dose(id: "manual:x", timestamp: at(2026, 11, 16, 17, 50), mg: 64)]), // asked drink is in the future
            (.init(mg: 60, at: at(2026, 11, 16, 12, 10), provenance: .typed), [Dose(id: "demo:1", timestamp: at(2026, 11, 16, 12), mg: 60)]), // Sample Data isn't a logged drink
            (.init(mg: 64, at: at(2026, 11, 16, 15), provenance: .typed), []),                       // nothing logged
        ]
        for (asked, doses) in cases {
            #expect(C.checkAskedDrink(asked, doses: doses, now: now) == .resolved(.notLogged(asked)))
        }
        // Exactly 30 minutes still asks.
        let edge = C.UnloggedDrink(mg: 64, at: at(2026, 11, 16, 15, 30), provenance: .typed)
        if case .needsChoice = C.checkAskedDrink(edge, doses: [logged], now: now) {} else { Issue.record("30 min should ask") }
        // Base evaluate labels its unlogged drink.
        #expect(C.evaluate(doses: [], unlogged: edge, halfLifeHours: 5, targets: [now], now: now).drinkLabel == "Not Logged")
        #expect(C.evaluate(doses: [], unlogged: nil, halfLifeHours: 5, targets: [now], now: now).drinkLabel == nil)
    }

    @Test func pastUnloggedDrinkIsAllowedUnlikeCutoffScenario() {
        // Asked at 22:00 about a drink at 15:00 that was never logged.
        let now = at(2026, 11, 16, 22)
        let drink = C.UnloggedDrink(mg: 95, at: at(2026, 11, 16, 15), provenance: .typed)
        let result = C.evaluate(doses: [], unlogged: drink, halfLifeHours: 5, targets: [now], now: now)
        #expect(result.problems.isEmpty)
        #expect(result.rows[0].totalMg == 95 * pow(0.5, 7.0 / 5))
        // CutoffScenario's guard is untouched: it still refuses a past hypothetical.
        let cutoff = CutoffScenario.evaluate(input: .init(bedtime: .init(year: 2026, month: 11, day: 16, hour: 23, minute: 0), thresholdMg: "50", drinkMg: "95", drinkTime: .init(year: 2026, month: 11, day: 16, hour: 15, minute: 0)),
                                             doses: [], halfLifeHours: 5, now: now, timeZone: la)
        #expect(cutoff.result.problems.contains(.drinkTimeBeforeCapture))
    }

    @Test func recordedSampleAndUnloggedKeptApart() {
        let now = at(2026, 11, 16, 18)
        let doses = [Dose(id: "manual:1", timestamp: at(2026, 11, 16, 8), mg: 95),
                     Dose(id: "demo:1", timestamp: at(2026, 11, 16, 12), mg: 60),
                     Dose(id: "manual:future", timestamp: at(2026, 11, 16, 20), mg: 200)]
        let drink = C.UnloggedDrink(mg: 80, at: at(2026, 11, 16, 19), provenance: .typed)
        let target = at(2026, 11, 16, 23)
        let result = C.evaluate(doses: doses, unlogged: drink, halfLifeHours: 5, targets: [target], now: now)
        let row = result.rows[0]
        #expect(row.recordedMg == Caffeine.activeMg(at: target, doses: [doses[0]], halfLifeHours: 5))
        #expect(row.sampleMg == Caffeine.activeMg(at: target, doses: [doses[1]], halfLifeHours: 5))
        #expect(row.unloggedMg == Caffeine.activeMg(at: target, doses: [Dose(id: "q", timestamp: drink.at, mg: 80)], halfLifeHours: 5))
        #expect(row.includesSample && result.includesSample)
        #expect(result.recordedCount == 1 && result.sampleCount == 1 && result.excludedFutureCount == 1)
    }

    @Test func nothingRecordedOrStatedIsNoRecordNeverZero() {
        let now = at(2026, 11, 16, 18)
        let result = C.evaluate(doses: [], unlogged: nil, halfLifeHours: 5, targets: [at(2026, 11, 16, 23)], now: now)
        #expect(result.rows[0].isNoRecord)
        #expect(result.rows[0].displayMg == nil)
        #expect(result.rows[0].valueText == "No record")
        // A drink after the queried time contributes nothing: still No record.
        let later = C.evaluate(doses: [], unlogged: .init(mg: 100, at: at(2026, 11, 17, 1), provenance: .typed), halfLifeHours: 5, targets: [at(2026, 11, 16, 23)], now: now)
        #expect(later.rows[0].valueText == "No record")
    }

    @Test func askingNeverChangesRecords() {
        let now = at(2026, 11, 16, 18)
        let doses = [Dose(id: "manual:1", timestamp: at(2026, 11, 16, 8), mg: 95)]
        let copy = doses
        let result = C.evaluate(doses: doses, unlogged: .init(mg: 126, at: now, provenance: .typed), halfLifeHours: 5, targets: [at(2026, 11, 16, 23)], now: now)
        #expect(doses == copy)
        #expect(result.unlogged?.provenance == .typed)
        #expect(result.unlogged?.label == "Not Logged")
        #expect(result.basis == ["manual:1|\(Int64(doses[0].timestamp))|95.0"])
    }

    @Test func provenanceKeepsDatabaseServing() {
        let now = at(2026, 11, 16, 18)
        let drink = C.UnloggedDrink(mg: 150, at: now, provenance: .database(entryID: "fdc-123", serving: "16 fl oz"))
        let result = C.evaluate(doses: [], unlogged: drink, halfLifeHours: 5, targets: [now], now: now)
        #expect(result.unlogged?.provenance == .database(entryID: "fdc-123", serving: "16 fl oz"))
    }

    @Test func invalidInputsReportProblemsAndNoNumbers() {
        let now = at(2026, 11, 16, 18)
        for bad in [0.0, -1, .nan, .infinity] {
            let r = C.evaluate(doses: [], unlogged: .init(mg: 100, at: now, provenance: .typed), halfLifeHours: bad, targets: [now], now: now)
            #expect(r.problems.contains(.invalidHalfLife) && r.rows.isEmpty)
        }
        for bad in [0.0, -5, .nan] {
            let r = C.evaluate(doses: [], unlogged: .init(mg: bad, at: now, provenance: .typed), halfLifeHours: 5, targets: [now], now: now)
            #expect(r.problems.contains(.invalidAmount) && r.rows.isEmpty)
        }
        let none = C.evaluate(doses: [], unlogged: nil, halfLifeHours: 5, targets: [], now: now)
        #expect(none.problems == [.missingTime])
    }

    @Test func dstRepeatedTimeUsesCutoffResolve() {
        // Clocks go back at 2:00 AM on Nov 1, 2026 in Los Angeles: 1:30 happens twice.
        let local = CutoffScenario.LocalTime(year: 2026, month: 11, day: 1, hour: 1, minute: 30)
        guard case .repeated(let first, let second) = CutoffScenario.resolve(local, in: la) else { Issue.record("expected repeated"); return }
        #expect(second - first == hourMs)
        let drink = C.UnloggedDrink(mg: 100, at: at(2026, 10, 31, 20), provenance: .typed)
        let rows = C.evaluate(doses: [], unlogged: drink, halfLifeHours: 5, targets: [first, second], now: at(2026, 10, 31, 19)).rows
        #expect(abs(rows[0].totalMg - 100 * pow(0.5, 5.5 / 5)) < 1e-9)
        #expect(abs(rows[1].totalMg - 100 * pow(0.5, 6.5 / 5)) < 1e-9)
        guard case .skipped = CutoffScenario.resolve(.init(year: 2026, month: 3, day: 8, hour: 2, minute: 30), in: la) else { Issue.record("expected skipped"); return }
    }

    @Test func halfLifeInfoCopy() {
        #expect(C.halfLifeInfo(5) == "Estimated with your half-life setting (5 h). In one study of 10 healthy young men, half-lives ranged from about 3 to 10 hours.")
        #expect(C.halfLifeInfo(6.5) == "Estimated with your half-life setting (6.5 h). In one study of 10 healthy young men, half-lives ranged from about 3 to 10 hours.")
        #expect(C.halfLifeRangeSource == "Blanchard & Sawers 1983")
        #expect(C.halfLifeRangeCitation == "Blanchard J, Sawers SJA. The absolute bioavailability of caffeine in man. Eur J Clin Pharmacol 1983;24:93–98. doi:10.1007/BF00613933. PubMed 6832208.")
        #expect(!C.halfLifeRangeCitation.contains("6886969") && !C.halfLifeRangeCitation.contains("BF01061844"))
    }

    @Test func copyHasNoForbiddenOrRejectedWords() {
        let chip = C.SleepTimeChip(minuteOfDay: 23 * 60 + 5, nights: 7)
        let strings = [C.title, C.notLoggedLabel, C.noRecordText, C.halfLifeInfo(5), C.halfLifeRangeSource, C.logThisDrinkLabel,
                       chip.label(clockTime: "11:05 PM"), "About 65 mg", C.lessThanFiveText, C.loggedLabel,
                       C.DuplicateChoice.useLogged.label, C.DuplicateChoice.addAnother.label]
        for s in strings {
            #expect(CopyRules.violations(in: s).isEmpty, "\(s)")
            for word in ["remaining", "impact", "moderate", "you'll lose", "should", "safe", "gardiner", "iom", "sugar", "nutrition", "recommend"] {
                #expect(!s.lowercased().contains(word), "\(s) contains \(word)")
            }
        }
        #expect(C.title == "Estimated Active Caffeine")
        #expect(C.logThisDrinkLabel == "Log This Drink")
    }

    // MARK: Sleep-time chip

    private func night(_ id: String, start: Millis, hours: Double, type: SleepType = .sleep) -> SleepSession {
        SleepSession(id: id, start: start, end: start + hours * hourMs, type: type)
    }

    @Test func fewerThanThreeNightsGivesNil() {
        let now = at(2026, 11, 16, 18)
        let sleeps = [night("manual:sleep:1", start: at(2026, 11, 14, 23), hours: 8), night("healthkit:sleep:sample:a", start: at(2026, 11, 15, 23), hours: 7)]
        #expect(C.recentSleepStart(sleeps, now: now, clock: clock) == nil)
    }

    @Test func threeNightsGiveMedianChipWithCount() {
        let now = at(2026, 11, 16, 18)
        let sleeps = [night("manual:sleep:1", start: at(2026, 11, 13, 22, 30), hours: 8),
                      night("healthkit:sleep:sample:a", start: at(2026, 11, 14, 23, 5), hours: 7),
                      night("healthkit:sleep:sample:b", start: at(2026, 11, 15, 23, 40), hours: 7)]
        let chip = C.recentSleepStart(sleeps, now: now, clock: clock)
        #expect(chip == C.SleepTimeChip(minuteOfDay: 23 * 60 + 5, nights: 3))
        #expect(chip?.label(clockTime: "11:05 PM") == "Recent Sleep Start · 11:05 PM · 3 Nights")
        #expect(chip?.nextStart(after: now, timeZone: la) == .exact(at(2026, 11, 16, 23, 5)))
    }

    @Test func medianIsSafeAcrossMidnight() {
        let now = at(2026, 11, 16, 18)
        let odd = [night("manual:sleep:1", start: at(2026, 11, 12, 23, 30), hours: 7),
                   night("manual:sleep:2", start: at(2026, 11, 14, 0, 15), hours: 7),
                   night("manual:sleep:3", start: at(2026, 11, 15, 0, 45), hours: 7)]
        #expect(C.recentSleepStart(odd, now: now, clock: clock)?.minuteOfDay == 15)
        let even = [night("manual:sleep:1", start: at(2026, 11, 11, 23), hours: 7),
                    night("manual:sleep:2", start: at(2026, 11, 12, 23, 30), hours: 7),
                    night("manual:sleep:3", start: at(2026, 11, 14, 0, 30), hours: 7),
                    night("manual:sleep:4", start: at(2026, 11, 15, 1), hours: 7)]
        #expect(C.recentSleepStart(even, now: now, clock: clock)?.minuteOfDay == 0)
    }

    @Test func manualAndHealthForSameNightCountOnce() {
        let now = at(2026, 11, 16, 18)
        let sleeps = [night("manual:sleep:1", start: at(2026, 11, 13, 23), hours: 8),
                      night("healthkit:sleep:sample:dup", start: at(2026, 11, 13, 23, 20), hours: 7.5), // same night, manual wins
                      night("healthkit:sleep:sample:b", start: at(2026, 11, 14, 23, 30), hours: 7)]
        #expect(C.recentSleepStart(sleeps, now: now, clock: clock) == nil)
        let chip = C.recentSleepStart(sleeps + [night("healthkit:sleep:sample:c", start: at(2026, 11, 15, 23, 50), hours: 7)], now: now, clock: clock)
        // Nights: 23:00 (manual, not 23:20), 23:30, 23:50 → median 23:30, 3 nights.
        #expect(chip == C.SleepTimeChip(minuteOfDay: 23 * 60 + 30, nights: 3))
    }

    @Test func excludesOldNapsSampleShortAndUnfinished() {
        let now = at(2026, 11, 16, 18)
        let base = [night("manual:sleep:1", start: at(2026, 11, 13, 23), hours: 8),
                    night("manual:sleep:2", start: at(2026, 11, 14, 23), hours: 8)]
        let noise = [night("manual:sleep:old", start: at(2026, 11, 1, 22), hours: 8),         // ended 15 days ago
                     night("manual:sleep:nap", start: at(2026, 11, 15, 14), hours: 4, type: .nap),
                     night("demo:sleep", start: at(2026, 11, 15, 22), hours: 8),
                     night("manual:sleep:short", start: at(2026, 11, 15, 3), hours: 2),
                     night("manual:sleep:open", start: at(2026, 11, 16, 14), hours: 8)]       // ends after now
        #expect(C.recentSleepStart(base + noise, now: now, clock: clock) == nil)
        // A night that ended 13 days ago still counts.
        let edge = night("manual:sleep:13d", start: at(2026, 11, 2, 23), hours: 8)
        #expect(C.recentSleepStart(base + noise + [edge], now: now, clock: clock)?.nights == 3)
    }

    @Test func targetSleepIsNeverUsed() {
        // The chip API takes sessions only; no Prefs, so targetSleep can't leak in.
        let now = at(2026, 11, 16, 18)
        #expect(C.recentSleepStart([], now: now, clock: clock) == nil)
    }

    // MARK: Route (deterministic, AI-off)

    private func parsed(_ text: String) -> Q.Parsed? {
        if case .caffeineAt(let p) = Q.route(text) { return p }
        return nil
    }

    @Test func aiOffPhrasesRouteToCaffeineAt() {
        let a = parsed("how much caffeine at 11pm")
        #expect(a == Q.Parsed(drinkMg: nil, drinkMentioned: false, drinkTime: nil, drinkDayOffset: 0, targets: [.clock(hour: 23, minute: 0)]))

        let b = parsed("How much will I have at bedtime?")
        #expect(b?.targets == [.sleepTime] && b?.drinkMg == nil)

        let c = parsed("if I drink 126mg now how much at 11")
        #expect(c == Q.Parsed(drinkMg: 126, drinkMentioned: true, drinkTime: .now, drinkDayOffset: 0, targets: [.ambiguousHour(hour: 11, minute: 0)]))

        #expect(parsed("how much caffeine is active at 11")?.targets == [.ambiguousHour(hour: 11, minute: 0)])
        #expect(parsed("how much caffeine will be in my system at midnight")?.targets == [.clock(hour: 0, minute: 0)])
        #expect(parsed("How much caffeine will I have tonight?")?.targets == [.sleepTime])
        #expect(parsed("how much caffeine at 10pm and 1am")?.targets == [.clock(hour: 22, minute: 0), .clock(hour: 1, minute: 0)])
        #expect(parsed("how much caffeine will I have at 23:30")?.targets == [.clock(hour: 23, minute: 30)])

        let past = parsed("I had 126 mg at 5:27 pm, how much is active at 11 pm?")
        #expect(past == Q.Parsed(drinkMg: 126, drinkMentioned: true, drinkTime: .clock(hour: 17, minute: 27), drinkDayOffset: 0, targets: [.clock(hour: 23, minute: 0)]))
        let suffix = parsed("how much caffeine at 11pm if I had 200mg at 2pm yesterday")
        #expect(suffix?.drinkMg == 200 && suffix?.drinkTime == .clock(hour: 14, minute: 0) && suffix?.drinkDayOffset == -1 && suffix?.targets == [.clock(hour: 23, minute: 0)])
    }

    @Test func mgQuestionWithoutHowMuch() {
        let p = parsed("126mg impact into 5pm?")
        #expect(p == Q.Parsed(drinkMg: 126, drinkMentioned: true, drinkTime: .into(hour: 17, minute: 0), drinkDayOffset: 0, targets: []))
        #expect(parsed("what does 126 mg at 5:27pm mean for tonight?")?.targets == [.sleepTime])
        // A bare "at 5" is ambiguous and is asked, never guessed.
        #expect(parsed("what about 126 mg at 5?")?.drinkTime == .ambiguousHour(hour: 5, minute: 0))
        // Logging sentences are not questions.
        #expect(Q.route("I had 126mg coffee at 5pm") == nil)
        #expect(Q.route("log 126mg at 5pm") == nil)
    }

    @Test func adviceQuestionsStayUnsupported() {
        for text in ["how much should I drink", "How much caffeine should I drink at 3pm?", "how much can I drink before bedtime",
                     "how much more caffeine can I have tonight", "how much is safe at 11pm", "recommend a dose for tonight",
                     "how much coffee is ok to drink at 4pm", "how much caffeine am I allowed at 9pm", "how much caffeine to drink at 2pm"] {
            #expect(Q.route(text) == .unsupported, "\(text)")
            #expect(AssistantPlanner.explicitIntent(text) == .unsupported, "\(text)")
        }
    }

    @Test func unrelatedOrTimelessTextIsNotThisRoute() {
        for text in ["how much sleep did I get", "how much caffeine", "log caffeine", "what's my energy tonight",
                     "how much time until 5pm", "show my history"] {
            #expect(Q.route(text) == nil, "\(text)")
        }
        // Existing behavior is unchanged: any "how much" is still .unsupported in explicitIntent.
        #expect(AssistantPlanner.explicitIntent("how much caffeine at 11pm") == .unsupported)
    }

    @Test func pastTenseQuestionsGetCapabilityChipsNotADeadEnd() {
        for text in ["how much caffeine did I have at 3pm", "How much was active at noon?", "how much caffeine was in me at 9am yesterday",
                     "how much caffeine did I have today", "how much caffeine were there at lunch"] {
            #expect(Q.route(text) == .showCapabilities, "\(text)")
            #expect(AssistantPlanner.explicitIntent(text) == .unsupported, "\(text)")
        }
        // The chips are the standard list, the same one the "What can you do?" card uses.
        #expect(Q.fallbackCapabilities == Capabilities.all.map(\.intent))
        // Past tense inside the drink clause doesn't change the question.
        #expect(Q.route("how much caffeine at 11pm if I had a drink that was 200mg at 2pm")?.isCaffeineAt == true)
        // Advice still wins over past tense.
        #expect(Q.route("how much should I have had at 3pm") == .unsupported)
    }

    @Test func timeChipsResolveWithoutGuessing() {
        let now = at(2026, 11, 16, 18, 4)
        // "at 11": two chips, never one picked.
        #expect(Q.choices(for: .ambiguousHour(hour: 11, minute: 0)) == [.clock(hour: 11, minute: 0), .clock(hour: 23, minute: 0)])
        #expect(Q.choices(for: .ambiguousHour(hour: 12, minute: 30)) == [.clock(hour: 0, minute: 30), .clock(hour: 12, minute: 30)])
        // "into 5pm": "At 5:00 PM" or "Now".
        #expect(Q.choices(for: .into(hour: 17, minute: 0)) == [.clock(hour: 17, minute: 0), .now])
        #expect(Q.choices(for: .sleepTime) == [])
        // Targets: the first occurrence after the anchor (drink time or now).
        #expect(Q.targetLocalTime(hour: 23, minute: 0, after: now, timeZone: la) == .init(year: 2026, month: 11, day: 16, hour: 23, minute: 0))
        #expect(Q.targetLocalTime(hour: 1, minute: 0, after: now, timeZone: la) == .init(year: 2026, month: 11, day: 17, hour: 1, minute: 0))
        // Drink times are today (or yesterday), past allowed.
        #expect(Q.drinkLocalTime(hour: 17, minute: 27, dayOffset: 0, now: now, timeZone: la) == .init(year: 2026, month: 11, day: 16, hour: 17, minute: 27))
        #expect(Q.drinkLocalTime(hour: 14, minute: 0, dayOffset: -1, now: now, timeZone: la) == .init(year: 2026, month: 11, day: 15, hour: 14, minute: 0))
    }

    // MARK: Amount contract (Codex P1, Nov 16)

    @Test func anAmountOutsideTheSaveContractIsRejectedWithoutATrap() {
        let now = at(2026, 11, 16, 18)
        for mg in [1e20, 2000, 0, -126, 12.5, .infinity, .nan] {
            let result = C.evaluate(doses: [], unlogged: .init(mg: mg, at: now, provenance: .typed), halfLifeHours: 5, targets: [now], now: now)
            #expect(result.problems.contains(.invalidAmount), "\(mg)")
            #expect(result.rows.isEmpty, "\(mg)")
        }
        // Normal amounts are unchanged, at both ends of the range.
        for mg in [1.0, 126, 1999] {
            let result = C.evaluate(doses: [], unlogged: .init(mg: mg, at: now, provenance: .typed), halfLifeHours: 5, targets: [now], now: now)
            #expect(result.problems.isEmpty, "\(mg)")
            #expect(result.rows.first?.totalMg == mg, "\(mg)")
        }
        #expect(CaffeineLog.isValidAmount(1999) && !CaffeineLog.isValidAmount(2000) && !CaffeineLog.isValidAmount(1e20))
    }

    @Test func displayRoundingNeverTraps() {
        #expect(C.displayMg(1e20) > 0)
        #expect(C.displayMg(-1e20) < 0)
        #expect(C.displayMg(.infinity) == 0 && C.displayMg(.nan) == 0)
        #expect(C.displayMg(67.1) == 65 && C.displayMg(62.5) == 65)
        // A recorded dose from elsewhere with an absurd amount still renders.
        let now = at(2026, 11, 16, 18)
        let row = C.evaluate(doses: [Dose(id: "x", timestamp: now, mg: 1e20)], unlogged: nil, halfLifeHours: 5, targets: [now], now: now).rows.first
        #expect(row?.valueText.isEmpty == false)
    }

    @Test func aTwentyOneDigitAmountAsksForAnAmountInRange() {
        let text = "how much caffeine at 11pm if I drink 100000000000000000000mg now"
        #expect(Q.route(text) == .clarify(Q.amountClarification))
        #expect(Q.route("what about 2000 mg at 5pm?") == .clarify(Q.amountClarification))
        #expect(Q.route("if I drink 126mg now how much at 11pm")?.isCaffeineAt == true)
        #expect(Q.route("if I drink 1999mg now how much at 11pm")?.isCaffeineAt == true)
    }

    // MARK: Numeric tokens (Codex P2, Nov 16)

    @Test func signedGroupedOrMalformedAmountsAskAgainNeverLoseASignOrGroup() {
        for token in ["-126mg", "−126mg", "+126mg", "1,126mg", "1.2.3mg", "126.mg", "1,126 mg"] {
            #expect(Q.route("how much caffeine at 11pm if I drank \(token) at 5pm") == .clarify(Q.amountClarification), "\(token)")
            #expect(Q.route("what about \(token) at 5pm?") == .clarify(Q.amountClarification), "\(token)")
        }
        let plain = Q.route("how much caffeine at 11pm if I drank 126mg at 5pm")
        if case .caffeineAt(let p)? = plain { #expect(p.drinkMg == 126) } else { Issue.record("126mg did not route") }
        if case .caffeineAt(let p)? = Q.route("what about 126 mg at 5pm?") { #expect(p.drinkMg == 126) } else { Issue.record("126 mg did not route") }
    }

    @Test func theSharedTokenRuleReadsOnlyPlainNumbers() {
        #expect(MgToken.matches(in: "126mg").map(\.value) == [126])
        #expect(MgToken.matches(in: "had 126 mg").map(\.value) == [126])
        for text in ["-126mg", "1,126mg", "1.2.3mg", "matcha -126mg", "drink-126mg", "+5mg"] {
            let found = MgToken.matches(in: text)
            #expect(found.count == 1 && found[0].value == nil, "\(text)")
        }
        #expect(MgToken.matches(in: "126mg and 80mg").count == 2)
        #expect(MgToken.matches(in: "12 oz latte").isEmpty)
    }

    @Test func typedEntriesWithASignedAmountAskAgainAndNeverKeepTheDigits() {
        let now = at(2026, 11, 16, 14)
        for text in ["matcha -126mg", "Starbucks -126mg", "coffee 1,126mg", "tea 1.2.3mg", "espresso -64 mg"] {
            guard case .unreadable(let message)? = TypedDrinkEntry.parse(text, db: CaffeineDatabase.bundled, now: now, clock: clock) else {
                Issue.record("\(text) was read as an entry"); continue
            }
            #expect(message == TypedDrinkEntry.amountRangeMessage, "\(text)")
        }
        // Matcha and Not in Database brands still go to manual entry with no amount.
        for text in ["matcha", "Starbucks latte"] {
            if case .entry(let entry)? = TypedDrinkEntry.parse(text, db: CaffeineDatabase.bundled, now: now, clock: clock) {
                #expect(entry.draft.mg.isEmpty && entry.amountSource == .none, "\(text)")
            } else { Issue.record("\(text) not an entry") }
        }
        if case .entry(let entry)? = TypedDrinkEntry.parse("matcha 70mg", db: CaffeineDatabase.bundled, now: now, clock: clock) {
            #expect(entry.draft.mg == "70" && entry.amountSource == .typedMg)
        } else { Issue.record("matcha 70mg not an entry") }
    }

    // MARK: Sleep chip and clock changes (Codex P2, Nov 16)

    @Test func theSleepChipResolvesLikeEveryOtherTimeOnANormalDay() {
        let chip = C.SleepTimeChip(minuteOfDay: 23 * 60 + 10, nights: 4)
        #expect(chip.nextStart(after: at(2026, 11, 16, 18), timeZone: la) == .exact(at(2026, 11, 16, 23, 10)))
        // Already past tonight's: tomorrow's.
        #expect(chip.nextStart(after: at(2026, 11, 16, 23, 30), timeZone: la) == .exact(at(2026, 11, 17, 23, 10)))
        let early = C.SleepTimeChip(minuteOfDay: 30, nights: 4)
        #expect(early.nextStart(after: at(2026, 11, 16, 18), timeZone: la) == .exact(at(2026, 11, 17, 0, 30)))
    }

    @Test func aSkippedSleepTimeIsReportedNotShifted() {
        let now = at(2026, 3, 8, 0, 30)
        let chip = C.SleepTimeChip(minuteOfDay: 2 * 60 + 30, nights: 4)
        let resolver = CutoffScenario.resolve(.init(year: 2026, month: 3, day: 8, hour: 2, minute: 30), in: la)
        #expect(resolver == .skipped)
        #expect(chip.nextStart(after: now, timeZone: la) == .skipped)
    }

    @Test func aRepeatedSleepTimeOffersBothNeverPicksOne() {
        let now = at(2026, 11, 1, 0, 30)
        let chip = C.SleepTimeChip(minuteOfDay: 90, nights: 4)
        let resolver = CutoffScenario.resolve(.init(year: 2026, month: 11, day: 1, hour: 1, minute: 30), in: la)
        guard case .repeated(let first, let second) = resolver else { Issue.record("resolver: \(resolver)"); return }
        #expect(second - first == hourMs)
        #expect(chip.nextStart(after: now, timeZone: la) == .repeated(first: first, second: second))
    }

    // MARK: Questions never become typed entries (Duet/Codex P2, Nov 16)

    @Test func questionCuesNeverBecomeATypedEntry() {
        let now = at(2026, 11, 16, 18)
        for text in ["200mg at 4pm what about bedtime", "100mg at 3pm impact tonight", "100mg difference",
                     "how about 100mg at 3pm", "100mg effect", "100mg at 3pm affect bedtime", "what if 100mg at 3pm",
                     "100mg at 3pm?", "espresso at bedtime", "coffee tonight"] {
            #expect(TypedDrinkEntry.parse(text, db: CaffeineDatabase.bundled, now: now, clock: clock) == nil, "\(text)")
        }
        // The follow-up route takes these questions first in the app.
        #expect(Q.route("200mg at 4pm what about bedtime")?.isCaffeineAt == true)
        #expect(Q.route("100mg at 3pm impact tonight")?.isCaffeineAt == true)
    }

    @Test func legitimateCustomDrinkNamesStillParse() throws {
        let now = at(2026, 11, 16, 18)
        for (text, source, mg) in [("Yerba Mate 80mg", "Yerba Mate", "80"), ("guayusa 90mg at 3pm", "Guayusa", "90")] {
            guard case .entry(let entry)? = TypedDrinkEntry.parse(text, db: CaffeineDatabase.bundled, now: now, clock: clock) else {
                Issue.record("\(text) not an entry"); continue
            }
            // The name may come from a matching record ("SWITCHEL · YERBA MATE"); the typed mg is kept.
            #expect(entry.draft.source.lowercased().contains(source.lowercased()), "\(text): \(entry)")
            #expect(entry.draft.mg == mg && entry.amountSource == .typedMg, "\(text): \(entry)")
        }
    }

    // MARK: Day words (Duet/Codex P2, Nov 16)

    private func parsedDay(_ text: String) -> Q.Parsed? {
        if case .caffeineAt(let p) = Q.route(text) { return p }
        return nil
    }

    @Test func tomorrowAndTodayKeepTheirDate() {
        let tomorrow = parsedDay("how much caffeine at 9am tomorrow")
        #expect(tomorrow?.targets == [.clock(hour: 9, minute: 0)] && tomorrow?.targetDay == .tomorrow)
        let today = parsedDay("how much caffeine at 9pm today")
        #expect(today?.targets == [.clock(hour: 21, minute: 0)] && today?.targetDay == .today)
        // No day word: the next occurrence, as before.
        let plain = parsedDay("how much caffeine at 9am")
        #expect(plain?.targets == [.clock(hour: 9, minute: 0)] && plain?.targetDay == nil)
        // "tonight" with a clock time is that evening's time, not the sleep chip.
        #expect(parsedDay("how much caffeine at 11pm tonight")?.targets == [.clock(hour: 23, minute: 0)])
        #expect(parsedDay("How much caffeine will I have tonight?")?.targets == [.sleepTime])
        #expect(parsedDay("how much caffeine at bedtime tonight")?.targets == [.sleepTime])
        #expect(parsedDay("how much caffeine at 11 tonight")?.targets == [.clock(hour: 23, minute: 0)])
        #expect(Q.route("how much caffeine at 9am tonight") == .clarify(Q.dayClarification))
    }

    @Test func pastAndUnsupportedDaysNeverBecomeAnotherDate() {
        #expect(Q.route("how much caffeine at 3pm yesterday") == .showCapabilities)
        #expect(Q.route("how much caffeine at 9am last night") == .showCapabilities)
        for text in ["how much caffeine on friday at 3pm", "how much caffeine at 3pm the day after tomorrow",
                     "how much caffeine at bedtime tomorrow", "how much caffeine at 9am today and tomorrow",
                     "what about 126 mg at 5pm tomorrow?", "how much caffeine at 11pm if I drink 100mg tomorrow at 9am"] {
            #expect(Q.route(text) == .clarify(Q.dayClarification), "\(text)")
        }
        // A drink yesterday is still supported.
        #expect(parsedDay("how much caffeine at 11pm if I had 200mg at 2pm yesterday")?.drinkDayOffset == -1)
    }
}

extension CaffeineQuestion.Route {
    var isCaffeineAt: Bool { if case .caffeineAt = self { return true } else { return false } }
}
