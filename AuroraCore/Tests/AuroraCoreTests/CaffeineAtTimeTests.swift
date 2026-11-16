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
        #expect(C.halfLifeInfo(5) == "Estimated with your half-life setting (5 h). Studies of healthy adults report half-lives from about 3 to 10 hours.")
        #expect(C.halfLifeInfo(6.5) == "Estimated with your half-life setting (6.5 h). Studies of healthy adults report half-lives from about 3 to 10 hours.")
        #expect(C.halfLifeRangeSource == "Blanchard & Sawers 1983")
    }

    @Test func copyHasNoForbiddenOrRejectedWords() {
        let chip = C.SleepTimeChip(minuteOfDay: 23 * 60 + 5, nights: 7)
        let strings = [C.title, C.notLoggedLabel, C.noRecordText, C.halfLifeInfo(5), C.halfLifeRangeSource, C.logThisDrinkLabel,
                       chip.label(clockTime: "11:05 PM"), "About 65 mg"]
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
        #expect(chip?.nextStart(after: now, clock: clock) == at(2026, 11, 16, 23, 5))
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
        for text in ["how much sleep did I get", "how much caffeine did I have today", "how much caffeine", "log caffeine", "what's my energy tonight",
                     "how much time until 5pm", "show my history", "how much caffeine did I have at 3pm", "how much was active at noon"] {
            #expect(Q.route(text) == nil, "\(text)")
        }
        // Existing behavior is unchanged: any "how much" is still .unsupported in explicitIntent.
        #expect(AssistantPlanner.explicitIntent("how much caffeine at 11pm") == .unsupported)
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
}
