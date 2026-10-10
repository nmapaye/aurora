import Foundation
import Testing
@testable import AuroraCore

@Suite struct CutoffScenarioTests {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    var text: DateText { .localized(locale: Locale(identifier: "en_US"), timeZone: la) }
    typealias S = CutoffScenario

    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> S.LocalTime { .init(year: y, month: m, day: d, hour: h, minute: mi) }
    private func instant(_ t: S.LocalTime, _ zone: TimeZone) -> Millis {
        guard case .exact(let ms) = S.resolve(t, in: zone) else { Issue.record("not exact"); return 0 }
        return ms
    }
    /// Noon on Oct 10 2026 in Los Angeles; bedtime 23:00 that night.
    private var now: Millis { instant(local(2026, 10, 10, 12), la) }
    private func input(threshold: String = "50", amount: String = "", drink: S.LocalTime? = nil) -> S.Input {
        .init(bedtime: local(2026, 10, 10, 23), thresholdMg: threshold, drinkMg: amount, drinkTime: drink)
    }
    private func run(_ input: S.Input, doses: [Dose] = [], halfLife: Double = 5, at time: Millis? = nil, zone: TimeZone? = nil) -> S.Snapshot {
        S.evaluate(input: input, doses: doses, halfLifeHours: halfLife, now: time ?? now, timeZone: zone ?? la)
    }

    @Test func existingMatchesBaselineDecay() {
        let doses = [Dose(id: "a", timestamp: now - 2 * hourMs, mg: 95), Dose(id: "b", timestamp: now - 30 * minuteMs, mg: 60)]
        let snapshot = run(input(), doses: doses)
        let bedtime = instant(local(2026, 10, 10, 23), la)
        #expect(snapshot.result.bedtime == bedtime)
        #expect(snapshot.result.existing?.totalMg == Caffeine.activeMg(at: bedtime, doses: doses, halfLifeHours: 5))
        #expect(snapshot.halfLifeHours == 5 && snapshot.timeZone == la.identifier && snapshot.capturedAt == now)
        #expect(snapshot.modelVersion == S.modelVersion)
    }

    @Test func emptyInputsStayEmptyWithNoDefaults() {
        let snapshot = run(.init())
        #expect(S.Input().thresholdMg.isEmpty && S.Input().drinkMg.isEmpty && S.Input().bedtime == nil)
        #expect(snapshot.result.problems == [.missingBedtime, .missingThreshold])
        #expect(snapshot.result.latest == .unavailable)
        #expect(snapshot.result.existing == nil && snapshot.result.thresholdMg == nil)
        #expect(S.reminder(for: snapshot, now: now, text: text) == nil)
    }

    @Test func noHypotheticalShowsExistingOnly() {
        let snapshot = run(input(), doses: [.init(id: "a", timestamp: now - hourMs, mg: 80)])
        #expect(snapshot.result.problems.isEmpty)
        #expect(snapshot.result.latest == .needsAmount)
        #expect(snapshot.result.hypotheticalMg == nil && snapshot.result.combinedMg == nil)
        #expect(snapshot.result.existing!.totalMg > 0)
    }

    @Test func thresholdBoundaries() throws {
        let bedtime = instant(local(2026, 10, 10, 23), la)
        // No records: headroom is the whole threshold.
        let equal = run(input(threshold: "50", amount: "50"))
        #expect(equal.result.latest == .feasible(bedtime))
        let doubled = run(input(threshold: "50", amount: "100"))
        #expect(doubled.result.latest == .feasible(bedtime - 5 * hourMs))
        let odd = run(input(threshold: "37", amount: "95"), doses: [.init(id: "a", timestamp: now - hourMs, mg: 40)])
        guard case .feasible(let time) = odd.result.latest else { Issue.record("expected feasible"); return }
        #expect(time.truncatingRemainder(dividingBy: minuteMs) == 0)
        func atBedtime(_ drinkAt: Millis) -> Double {
            Caffeine.activeMg(at: bedtime, doses: [.init(id: "a", timestamp: now - hourMs, mg: 40), .init(id: "h", timestamp: drinkAt, mg: 95)], halfLifeHours: 5)
        }
        // At or under at the time shown; above a minute later.
        #expect(atBedtime(time) <= 37)
        #expect(atBedtime(time + minuteMs) > 37)
    }

    @Test func combinedIncludesHypotheticalAtItsTime() {
        let snapshot = run(input(threshold: "50", amount: "100", drink: local(2026, 10, 10, 18)), doses: [.init(id: "a", timestamp: now, mg: 20)])
        #expect(snapshot.result.hypotheticalMg == 50)
        #expect(snapshot.result.combinedMg == snapshot.result.existing!.totalMg + 50)
    }

    @Test func existingAtOrAboveThreshold() {
        let doses = [Dose(id: "a", timestamp: now - hourMs, mg: 400)]
        #expect(run(input(threshold: "10", amount: "50"), doses: doses).result.latest == .thresholdReachedByRecords)
        #expect(run(input(threshold: "10"), doses: doses).result.latest == .thresholdReachedByRecords)
        // Exactly equal: 100 mg at bedtime from a 200 mg entry one half-life earlier.
        let bedtime = instant(local(2026, 10, 10, 23), la)
        let equal = [Dose(id: "b", timestamp: bedtime - 5 * hourMs - 6 * hourMs, mg: 400)]
        let existing = Caffeine.activeMg(at: bedtime, doses: equal, halfLifeHours: 5)
        let snapshot = run(input(threshold: numberText(existing), amount: "1"), doses: equal, at: bedtime - 6 * hourMs)
        #expect(snapshot.result.latest == .thresholdReachedByRecords)
    }

    @Test func pastCandidateAndZeroThreshold() {
        let late = instant(local(2026, 10, 10, 22), la)
        // 400 mg needs three half-lives under a 50 mg threshold: 15 hours before 11 PM.
        #expect(run(input(threshold: "50", amount: "400"), at: late).result.latest == .passed(instant(local(2026, 10, 10, 8), la)))
        #expect(run(input(threshold: "0", amount: "50")).result.latest == .unreachable)
        #expect(run(input(threshold: "0"), doses: [.init(id: "a", timestamp: now - hourMs, mg: 1)]).result.latest == .unreachable)
        #expect(run(input(threshold: "0")).result.latest == .needsAmount)
    }

    @Test(arguments: ["nan", "inf", "-inf", "-1", "abc", "1e999"]) func invalidThreshold(value: String) {
        let snapshot = run(input(threshold: value, amount: "50"))
        #expect(snapshot.result.problems == [.invalidThreshold])
        #expect(snapshot.result.latest == .unavailable)
    }

    @Test(arguments: ["0", "-5", "nan", "inf", "x"]) func invalidAmount(value: String) {
        let snapshot = run(input(amount: value))
        #expect(snapshot.result.problems == [.invalidAmount])
        #expect(snapshot.result.latest == .unavailable && snapshot.result.amountMg == nil)
    }

    @Test(arguments: [0, -5, Double.nan, Double.infinity]) func invalidHalfLife(value: Double) {
        let snapshot = run(input(amount: "50"), doses: [.init(id: "a", timestamp: now, mg: 50)], halfLife: value)
        #expect(snapshot.result.problems.contains(.invalidHalfLife))
        #expect(snapshot.result.existing == nil && snapshot.result.latest == .unavailable)
    }

    @Test func sampleAndFutureRecordsAreSeparated() {
        let doses = [
            Dose(id: "a", timestamp: now - hourMs, mg: 80),
            Dose(id: "demo:b", timestamp: now - hourMs, mg: 60),
            Dose(id: "c", timestamp: now + hourMs, mg: 200)
        ]
        let existing = run(input(), doses: doses).result.existing!
        let bedtime = instant(local(2026, 10, 10, 23), la)
        #expect(existing.recordedMg == Caffeine.activeMg(at: bedtime, doses: [doses[0]], halfLifeHours: 5))
        #expect(existing.sampleMg == Caffeine.activeMg(at: bedtime, doses: [doses[1]], halfLifeHours: 5))
        #expect(existing.recordedCount == 1 && existing.sampleCount == 1 && existing.includesSample)
        #expect(existing.excludedFutureCount == 1)
        #expect(run(input(), doses: doses).result.basis.allSatisfy { !$0.hasPrefix("c|") })
        #expect(run(input(), doses: []).result.existing?.totalMg == 0)
    }

    @Test func timesMustFollowCaptureAndPrecedeBedtime() {
        #expect(run(input(), at: instant(local(2026, 10, 10, 23), la)).result.problems == [.bedtimeNotAfterCapture])
        #expect(run(input(amount: "50", drink: local(2026, 10, 10, 11))).result.problems == [.drinkTimeBeforeCapture])
        let after = run(input(amount: "50", drink: local(2026, 10, 10, 23, 30)))
        #expect(after.result.problems == [.drinkTimeAfterBedtime])
        // A drink time problem still leaves the latest time computable.
        #expect(after.result.latest == .feasible(instant(local(2026, 10, 10, 23), la)))
        #expect(run(.init(bedtime: local(2026, 2, 30, 23), thresholdMg: "5")).result.problems == [.bedtimeInvalid])
    }

    // MARK: Daylight saving

    @Test(arguments: [
        ("America/Los_Angeles", (2026, 3, 8, 2, 30), (2026, 11, 1, 1, 30), 3600.0),
        ("Europe/London", (2026, 3, 29, 1, 30), (2026, 10, 25, 1, 30), 3600.0),
        ("Australia/Sydney", (2026, 10, 4, 2, 30), (2026, 4, 5, 2, 30), 3600.0),
        ("Australia/Lord_Howe", (2026, 10, 4, 2, 15), (2026, 4, 5, 1, 45), 1800.0)
    ]) func bothTransitionsResolveExplicitly(zoneID: String, skipped: (Int, Int, Int, Int, Int), repeated: (Int, Int, Int, Int, Int), shift: Double) {
        let zone = TimeZone(identifier: zoneID)!
        #expect(S.resolve(local(skipped.0, skipped.1, skipped.2, skipped.3, skipped.4), in: zone) == .skipped)
        guard case .repeated(let first, let second) = S.resolve(local(repeated.0, repeated.1, repeated.2, repeated.3, repeated.4), in: zone) else {
            Issue.record("expected repeated in \(zoneID)"); return
        }
        #expect(second - first == shift * 1000)
        #expect(S.resolve(local(2026, 7, 1, 12), in: TimeZone(identifier: "UTC")!) != .skipped)
    }

    @Test func repeatedBedtimeNeedsAChoiceAndSkippedIsNeverShifted() {
        let before = instant(local(2026, 10, 31, 20), la)
        var scenario = S.Input(bedtime: local(2026, 11, 1, 1, 30), thresholdMg: "50", drinkMg: "100")
        #expect(run(scenario, at: before).result.problems == [.bedtimeRepeated])
        scenario.bedtimeOccurrence = .first
        let first = run(scenario, at: before).result
        scenario.bedtimeOccurrence = .second
        let second = run(scenario, at: before).result
        #expect(second.bedtime! - first.bedtime! == hourMs)
        let skipped = run(.init(bedtime: local(2026, 3, 8, 2, 30), thresholdMg: "50"), at: instant(local(2026, 3, 7, 20), la))
        #expect(skipped.result.problems == [.bedtimeSkipped] && skipped.result.bedtime == nil)
    }

    @Test func decayAcrossFallBackCountsRealHours() {
        // 00:30 PDT to 03:30 PST is four hours, not three.
        let before = instant(local(2026, 10, 31, 20), la)
        let scenario = S.Input(bedtime: local(2026, 11, 1, 3, 30), thresholdMg: "500", drinkMg: "100", drinkTime: local(2026, 11, 1, 0, 30))
        let result = run(scenario, halfLife: 4, at: before).result
        #expect(result.bedtime! - result.drinkAt! == 4 * hourMs)
        #expect(result.hypotheticalMg == 50)
        // Spring forward: 01:30 PST to 03:30 PDT is one hour.
        let spring = S.Input(bedtime: local(2026, 3, 8, 3, 30), thresholdMg: "500", drinkMg: "100", drinkTime: local(2026, 3, 8, 1, 30))
        let sprung = run(spring, halfLife: 1, at: instant(local(2026, 3, 7, 20), la)).result
        #expect(sprung.hypotheticalMg == 50)
    }

    @Test func utcAndLosAngelesAgreeOnInstants() {
        let utc = TimeZone(identifier: "UTC")!
        let laBed = instant(local(2026, 10, 10, 23), la)
        let utcBed = instant(local(2026, 10, 11, 6), utc)
        #expect(laBed == utcBed)
        let a = run(input(threshold: "50", amount: "100"), doses: [.init(id: "a", timestamp: now - hourMs, mg: 30)])
        let b = run(.init(bedtime: local(2026, 10, 11, 6), thresholdMg: "50", drinkMg: "100"), doses: [.init(id: "a", timestamp: now - hourMs, mg: 30)], zone: utc)
        #expect(a.result.latest == b.result.latest && a.result.existing == b.result.existing)
    }

    // MARK: Snapshots and reminders

    @Test func snapshotRoundTripsAndOldCardsDecode() throws {
        var card = AssistantCards.cutoffScenario(input: input(amount: "100"), state: AppState(), now: now, clock: LocalClock(timeZone: la), text: text)
        card.cutoff?.reminder = .scheduled(fireAt: now + hourMs, savedAt: now)
        #expect(try JSONDecoder().decode(AssistantCard.self, from: JSONEncoder().encode(card)) == card)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AssistantCard(kind: .energy, capturedAt: now, title: "Old"))) as! [String: Any]
        old.removeValue(forKey: "cutoff")
        let decoded = try JSONDecoder().decode(AssistantCard.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.cutoff == nil && decoded.kind == .energy)
        #expect(card.refreshIntent == .cutoffScenario)
    }

    @Test func reminderCopyIsUserDefinedAndOnlyForFutureTimes() throws {
        let snapshot = run(input(threshold: "50", amount: "100"))
        let content = try #require(S.reminder(for: snapshot, now: now, text: text))
        #expect(content.fireAt == instant(local(2026, 10, 10, 18), la))
        #expect(content.body.contains("user-defined scenario, not a safety limit"))
        for copy in [content.title, content.body, S.disclaimer, S.assumption] + S.Problem.allCases.map({ $0.message(timeZone: "UTC") }) {
            #expect(CopyRules.violations(in: copy).isEmpty, "\(copy)")
        }
        #expect(S.reminder(for: snapshot, now: content.fireAt, text: text) == nil)
        #expect(S.reminder(for: run(input(threshold: "0", amount: "1")), now: now, text: text) == nil)
    }

    @Test func revalidationRequiresAnUnchangedContext() {
        let doses = [Dose(id: "a", timestamp: now - hourMs, mg: 30)]
        let scenario = input(threshold: "50", amount: "100")
        let preview = run(scenario, doses: doses)
        func check(_ input: S.Input = .init(), doses d: [Dose]? = nil, halfLife: Double = 5, at: Millis? = nil, zone: TimeZone? = nil) -> S.Revalidation {
            S.revalidate(preview, input: input == .init() ? scenario : input, doses: d ?? doses, halfLifeHours: halfLife, now: at ?? now + minuteMs, timeZone: zone ?? la, text: text)
        }
        guard case .current(let content) = check() else { Issue.record("expected current"); return }
        #expect(content == S.reminder(for: preview, now: now, text: text))
        #expect(check(doses: doses + [.init(id: "b", timestamp: now, mg: 10)]) != .current(content))
        // A record dated after capture doesn't change what's known yet.
        #expect(check(doses: doses + [.init(id: "f", timestamp: now + dayMs, mg: 10)]) == .current(content))
        #expect(check(input(threshold: "60", amount: "100")) != .current(content))
        #expect(check(halfLife: 6) != .current(content))
        #expect(check(zone: TimeZone(identifier: "UTC")!) != .current(content))
        guard case .feasible(let time) = preview.result.latest else { return }
        #expect(check(at: time + minuteMs) != .current(content))
    }

    @Test func plannerRoutesScenarioWithoutAdvice() {
        #expect(AssistantPlanner.explicitIntent("Cutoff scenario") == .cutoffScenario)
        #expect(AssistantPlanner.explicitIntent("show my caffeine cutoff what if") == .cutoffScenario)
        #expect(AssistantPlanner.explicitIntent("how much caffeine before my cutoff scenario?") == .unsupported)
        #expect(AssistantPlanner.explicitIntent("cutoff reminder") == .reminders)
        #expect(AssistantPlanner.modelIntent("cutoffScenario") == .cutoffScenario)
        #expect(CopyRules.violations(in: AssistantPlanner.modelInstructions).isEmpty)
    }
}
