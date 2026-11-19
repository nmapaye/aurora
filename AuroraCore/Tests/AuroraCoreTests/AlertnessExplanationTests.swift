import Foundation
import Testing
@testable import AuroraCore

struct AlertnessExplanationTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    /// Thu, Oct 8, 2026, noon UTC.
    static let base: Millis = 1_791_460_800_000

    func clock(_ zone: String) -> LocalClock { LocalClock(timeZone: TimeZone(identifier: zone)!) }
    func inputs(_ clock: LocalClock) -> EstimateInputs { EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: clock) }
    func night(_ id: String, endingAt end: Millis, hours: Double) -> SleepSession {
        SleepSession(id: id, start: end - hours * hourMs, end: end)
    }
    func explain(_ at: Millis, _ doses: [Dose], _ sleeps: [SleepSession], _ clock: LocalClock) -> (EnergyEstimate, AlertnessExplanation) {
        let estimate = EnergyEstimate.capture(at: at, doses: doses, sleeps: sleeps, inputs: inputs(clock))
        return (estimate, AlertnessExplanation.explain(estimate, text: fixtureText))
    }
    func factor(_ e: AlertnessExplanation, _ kind: AlertnessExplanation.Factor.Kind) -> AlertnessExplanation.Factor? {
        e.factors.first { $0.kind == kind }
    }
    /// Whole numbers in a line, ignoring the fixture's clock-time tokens.
    func numbers(_ line: String) -> [String] {
        let scrubbed = line.replacingOccurrences(of: #"T\d+"#, with: "", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        return regex.matches(in: scrubbed, range: NSRange(scrubbed.startIndex..., in: scrubbed)).map { String(scrubbed[Range($0.range, in: scrubbed)!]) }
    }

    @Test(arguments: zones) func missingNightSaysNoSleepRecordedNeverZero(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 10)
        let (estimate, e) = explain(now, [Dose(id: "a", timestamp: now - hourMs, mg: 95, source: "Drip")], [], clock)
        #expect(estimate.modeledScore == nil && e.score == nil && e.largest == nil)
        let sleep = factor(e, .sleep)
        #expect(sleep?.detail == "No sleep recorded in the last 24 hours.")
        #expect(sleep?.points == nil)
        // No score: no points anywhere, and no "0h"/"0 h"/"0m" for missing sleep.
        #expect(e.factors.allSatisfy { $0.points == nil })
        for line in e.allText {
            #expect(line.range(of: #"\b0\s?(h|m|hours?)\b"#, options: .regularExpression) == nil, "\(line)")
        }
        #expect(e.headline.contains(EnergyEstimate.missingSleepLine))
        // No reassurance lines: the card's "Modeled" label and Terms carry them.
        #expect(e.notes.isEmpty)
        #expect(factor(e, .start) == nil)
    }

    @Test(arguments: zones) func aNapAloneIsShownButGivesNoScore(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 16)
        let (_, e) = explain(now, [], [night("nap", endingAt: now - 2 * hourMs, hours: 1.5)], clock)
        #expect(e.score == nil)
        #expect(factor(e, .sleep)?.detail == "Recorded sleep in the last 24 hours: \(formatSleepHours(1.5)), but none is a block of 3 hours or more in the last 18 hours.")
        #expect(factor(e, .sleep)?.points == nil)
    }

    @Test(arguments: zones) func noCaffeineHasNoCaffeinePoints(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 11)
        let (estimate, e) = explain(now, [], [night("n", endingAt: clock.setTime(Self.base, hour: 7), hours: 7)], clock)
        #expect(estimate.modeledScore != nil)
        let caffeine = factor(e, .caffeine)
        #expect(caffeine?.points == nil)
        #expect(caffeine?.detail == "No caffeine recorded by this time.")
        #expect(e.largest != .caffeine)
    }

    @Test(arguments: zones) func valuesMatchTheEstimator(zone: String) throws {
        let clock = clock(zone)
        for hour in [7, 9, 13, 15, 21] {
            let now = clock.setTime(Self.base, hour: hour, minute: 20)
            let wake = clock.setTime(Self.base, hour: 6, minute: 50)
            let doses = [Dose(id: "a", timestamp: wake + 30 * minuteMs, mg: 95, source: "Drip"),
                         Dose(id: "demo:b", timestamp: now - 3 * hourMs, mg: 160, source: "Energy")]
            let sleeps = [night("n", endingAt: wake, hours: 5.75)]
            let known = (doses.filter { $0.timestamp <= now }, sleeps)
            let (estimate, e) = explain(now, known.0, known.1, clock)
            let direct = Summary.estimateAlertness(at: now, doses: known.0, sleeps: known.1, inputs: inputs(clock))
            let score = try #require(direct.score)
            #expect(e.score == score && estimate.modeledScore == score)
            #expect(e.headline.hasPrefix("\(EnergyEstimate.title) \(score) of 100"))
            let raw = Alertness.score(at: now, doses: known.0, sleeps: known.1, halfLifeHours: 5, targetSleepHours: 8, clock: clock)
            #expect(abs((estimate.unroundedScore ?? -1) - raw) < 1e-9)
            // Each point figure is the estimator's own term, rounded.
            let terms: [(AlertnessExplanation.Factor.Kind, Double)] = [
                (.sleep, -Alertness.sleepDebtWeight * SleepDebt.value(at: now, sleeps: known.1, targetHours: 8)),
                (.caffeine, Alertness.caffeineWeight * Caffeine.activeEffect(at: now, doses: known.0, halfLifeHours: 5)),
                (.timeOfDay, Alertness.circadianWeight * Circadian.value(at: now, clock: clock)),
            ]
            for (kind, points) in terms {
                let value = jsRoundInt(points)
                let expected = value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
                #expect(factor(e, kind)?.points == expected, "\(kind) at \(hour)")
            }
            let inertia = SleepInertia.value(at: now, sleeps: known.1)
            #expect((factor(e, .wakeUp) != nil) == (inertia > 0))
            #expect(factor(e, .sleep)?.detail.contains(formatSleepHours(SleepDebt.totalHoursLast24(at: now, sleeps: known.1))) == true)
            let active = numberText(jsRound(Caffeine.activeMg(at: now, doses: known.0, halfLifeHours: 5)))
            #expect(factor(e, .caffeine)?.detail.hasPrefix("\(active) mg") == true)
            // Sample Data stays labeled (the card shows its badge).
            #expect(e.includesSample)
            // The starting point is the estimator's own baseline.
            #expect(factor(e, .start)?.points == estimate.contributions.first { $0.kind == .baseline }?.pointsText)
        }
    }

    /// Every number shown traces to the estimate or a documented model constant.
    @Test(arguments: zones) func showsNoNumberTheModelDidNotCompute(zone: String) {
        let clock = clock(zone)
        let scenarios: [(Millis, [Dose], [SleepSession])] = [
            (clock.setTime(Self.base, hour: 7, minute: 10), [], [night("n", endingAt: clock.setTime(Self.base, hour: 7), hours: 8.5)]),
            (clock.setTime(Self.base, hour: 14), [Dose(id: "a", timestamp: clock.setTime(Self.base, hour: 9), mg: 200)], [night("n", endingAt: clock.setTime(Self.base, hour: 6), hours: 4)]),
            (clock.setTime(Self.base, hour: 3), [Dose(id: "a", timestamp: clock.setTime(Self.base, hour: 1), mg: 1500)], [night("n", endingAt: clock.setTime(Self.base, hour: 0), hours: 10)]),
            (clock.setTime(Self.base, hour: 10), [], []),
        ]
        for (now, doses, sleeps) in scenarios {
            let (estimate, e) = explain(now, doses, sleeps, clock)
            var allowed = Set(["100", "0", "3", "18", "24"])  // scale, eligibility rule, window
            allowed.formUnion(estimate.modeledScore.map { [String($0)] } ?? [])
            allowed.formUnion(estimate.contributions.flatMap { numbers($0.pointsText) })
            allowed.formUnion(numbers(formatSleepHours(estimate.sleepHoursLast24)))
            allowed.formUnion([numberText(estimate.targetSleepHours), numberText(estimate.halfLifeHours), numberText(jsRound(estimate.evidence.activeCaffeineMg))])
            for line in e.allText {
                for number in numbers(line) { #expect(allowed.contains(number), "\(number) in \(line)") }
                #expect(CopyRules.violations(in: line).isEmpty, "\(line)")
            }
        }
    }

    @Test func clampedScoresSayTheScaleStops() {
        let clock = clock("UTC")
        let now = clock.setTime(Self.base, hour: 15)
        let (estimate, e) = explain(now, [Dose(id: "a", timestamp: now - minuteMs, mg: 1500)], [night("n", endingAt: now - 6 * hourMs, hours: 9)], clock)
        #expect(estimate.modeledScore == 100)
        #expect(e.notes.contains("The parts add up to more than 100, and the scale stops at 100."))
    }
}
