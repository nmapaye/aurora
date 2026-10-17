import Foundation
import Testing
@testable import AuroraCore

/// With no sleep target, the model's sleep-target term compares with the
/// person's own usual sleep: the median of main sleeps in the last 14 days,
/// last night excluded, from 7 nights.
@Suite("Usual sleep as the reference when no target is set")
struct UsualSleepBaselineTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    static func clock(_ zone: String) -> LocalClock { LocalClock(timeZone: TimeZone(identifier: zone)!) }

    /// 2026-03-12, a few days after the US spring-forward change.
    static let base: Millis = 1_773_316_800_000
    /// Local noon on that day, after last night's wake-up in either zone.
    static func t(_ clock: LocalClock) -> Millis { clock.setTime(base, hour: 12) }

    /// A main sleep waking at `wakeHour` local, `back` days before `t`'s day.
    static func night(_ back: Int, hours: Double, t: Millis, clock: LocalClock, wakeHour: Int = 7, id: String? = nil) -> SleepSession {
        let wake = clock.setTime(clock.addingDays(-back, to: t), hour: wakeHour)
        return SleepSession(id: id ?? "healthkit:sleep:sample:n\(back)", start: wake - hours * hourMs, end: wake)
    }

    /// Last night (`back` 0) plus earlier nights of `hours`, newest first.
    static func history(_ hours: [Double], lastNight: Double = 7, t: Millis, clock: LocalClock) -> [SleepSession] {
        [night(0, hours: lastNight, t: t, clock: clock)] + hours.enumerated().map { night($0.offset + 1, hours: $0.element, t: t, clock: clock) }
    }

    static func inputs(_ clock: LocalClock, target: Double? = nil) -> EstimateInputs {
        EstimateInputs(halfLifeHours: 5, targetSleepHours: target, clock: clock)
    }

    @Test(arguments: zones) func fewerThanSevenEarlierNightsLeaveTheTermOut(zone: String) {
        let clock = Self.clock(zone)
        let sleeps = Self.history([7, 7, 7, 7, 7, 7], t: Self.t(clock), clock: clock)
        #expect(UsualSleepDuration.baseline(sleeps, at: Self.t(clock), clock: clock) == nil)
        let estimate = EnergyEstimate.capture(at: Self.t(clock), doses: [], sleeps: sleeps, inputs: Self.inputs(clock))
        #expect(estimate.usualSleep == nil)
        #expect(estimate.missingInputs.contains(.sleepTarget))
        #expect(!estimate.contributions.contains { $0.kind == .sleepDebt })
        #expect(estimate.sleepReferenceText == "No sleep target set.")
    }

    @Test(arguments: zones) func sevenNightsUseTheMedianOddAndEven(zone: String) throws {
        let clock = Self.clock(zone)
        let odd = Self.history([6, 7, 8, 6.5, 7.5, 9, 5], t: Self.t(clock), clock: clock)
        let oddBaseline = try #require(UsualSleepDuration.baseline(odd, at: Self.t(clock), clock: clock))
        #expect(oddBaseline.nights == 7 && oddBaseline.asleepMs == 7 * hourMs)
        let even = Self.history([6, 7, 8, 6.5, 7.5, 9, 5, 8.5], t: Self.t(clock), clock: clock)
        let evenBaseline = try #require(UsualSleepDuration.baseline(even, at: Self.t(clock), clock: clock))
        #expect(evenBaseline.nights == 8 && evenBaseline.asleepMs == 7.25 * hourMs)

        // The model's term uses it in place of a target, and says so.
        let estimate = EnergyEstimate.capture(at: Self.t(clock), doses: [], sleeps: odd, inputs: Self.inputs(clock))
        #expect(estimate.usualSleep == oddBaseline)
        #expect(estimate.targetSleepHours == nil)
        #expect(!estimate.missingInputs.contains(.sleepTarget))
        let debt = try #require(estimate.contributions.first { $0.kind == .sleepDebt })
        #expect(debt.term == SleepDebt.value(at: Self.t(clock), sleeps: odd, targetHours: 7))
        #expect(approxEqual(estimate.unroundedScore, Alertness.score(at: Self.t(clock), doses: [], sleeps: odd, halfLifeHours: 5, targetSleepHours: 7, clock: clock)))
        #expect(estimate.sleepReferenceText == "Compared with your usual 7h 0m (median of 7 nights). Not a recommendation.")
        #expect(CopyRules.violations(in: oddBaseline.text + evenBaseline.text).isEmpty)
        #expect(Summary.estimateAlertness(at: Self.t(clock), doses: [], sleeps: odd, inputs: Self.inputs(clock)).score == estimate.modeledScore)
    }

    @Test(arguments: zones) func lastNightIsExcluded(zone: String) throws {
        let clock = Self.clock(zone)
        let earlier = [7.0, 7, 7, 7, 7, 7, 7]
        let short = try #require(UsualSleepDuration.baseline(Self.history(earlier, lastNight: 3, t: Self.t(clock), clock: clock), at: Self.t(clock), clock: clock))
        let long = try #require(UsualSleepDuration.baseline(Self.history(earlier, lastNight: 11, t: Self.t(clock), clock: clock), at: Self.t(clock), clock: clock))
        #expect(short == long && short.asleepMs == 7 * hourMs && short.nights == 7)
        // A short night therefore lowers the score against the usual 7 h.
        let estimate = EnergyEstimate.capture(at: Self.t(clock), doses: [], sleeps: Self.history(earlier, lastNight: 3, t: Self.t(clock), clock: clock), inputs: Self.inputs(clock))
        #expect(try #require(estimate.contributions.first { $0.kind == .sleepDebt }).term > 0)
    }

    @Test(arguments: zones) func aChosenTargetAlwaysWins(zone: String) {
        let clock = Self.clock(zone)
        let sleeps = Self.history([6, 6, 6, 6, 6, 6, 6], t: Self.t(clock), clock: clock)
        #expect(Self.inputs(clock, target: 8).sleepReference(at: Self.t(clock), sleeps: sleeps) == .target(8))
        let estimate = EnergyEstimate.capture(at: Self.t(clock), doses: [], sleeps: sleeps, inputs: Self.inputs(clock, target: 8))
        #expect(estimate.usualSleep == nil && estimate.targetSleepHours == 8)
        #expect(estimate.sleepReferenceText == "Your goal: 8h.")
        // The baseline is never stored as the target.
        var state = AppState()
        state.sleeps = sleeps
        _ = EnergySnapshot.capture(state: state, now: Self.t(clock), clock: clock, includeProjection: false)
        #expect(state.prefs.targetSleep == nil)
    }

    @Test(arguments: zones) func napsShortAndSecondarySleepAreNotCounted(zone: String) throws {
        let clock = Self.clock(zone)
        var sleeps = Self.history([7, 7, 7, 7, 7, 7], t: Self.t(clock), clock: clock)
        // Six earlier mains: under the gate whatever else is recorded.
        for back in 1...6 {
            // A typed nap, a short sample and a secondary sleep each day.
            let day = clock.addingDays(-back, to: Self.t(clock))
            let nap = clock.setTime(day, hour: 15)
            sleeps.append(SleepSession(id: "manual:sleep:nap\(back)", start: nap, end: nap + hourMs, type: .nap))
            let doze = clock.setTime(day, hour: 19)
            sleeps.append(SleepSession(id: "healthkit:sleep:sample:short\(back)", start: doze, end: doze + 45 * minuteMs))
            let early = clock.setTime(day, hour: 9, minute: 30)
            sleeps.append(SleepSession(id: "healthkit:sleep:sample:second\(back)", start: early, end: early + 3.25 * hourMs))
        }
        let kinds = Set(SleepEpisodes.build(sleeps, now: Self.t(clock), clock: clock).map(\.kind))
        #expect(kinds == [.main, .nap, .short, .secondary])
        #expect(UsualSleepDuration.baseline(sleeps, at: Self.t(clock), clock: clock) == nil)
        // One more main sleep reaches the gate; the others still don't count.
        sleeps.append(Self.night(7, hours: 7, t: Self.t(clock), clock: clock))
        let baseline = try #require(UsualSleepDuration.baseline(sleeps, at: Self.t(clock), clock: clock))
        #expect(baseline.nights == 7 && baseline.asleepMs == 7 * hourMs)
    }

    @Test(arguments: zones) func windowIsFourteenDays(zone: String) {
        let clock = Self.clock(zone)
        // Seven earlier mains, but the oldest woke 15 days ago.
        let sleeps = Self.history([7, 7, 7, 7, 7, 7], t: Self.t(clock), clock: clock) + [Self.night(15, hours: 7, t: Self.t(clock), clock: clock)]
        #expect(UsualSleepDuration.baseline(sleeps, at: Self.t(clock), clock: clock) == nil)
    }

    @Test(arguments: zones) func nightsWakingJustAfterMidnightAndAcrossDST(zone: String) throws {
        let clock = Self.clock(zone)
        // Late sleepers: 17:00–00:30, so each wakes just after midnight.
        let late = (0...7).map { Self.night($0, hours: 7.5, t: Self.t(clock), clock: clock, wakeHour: 0) }
            .map { SleepSession(id: $0.id, start: $0.start + 30 * minuteMs, end: $0.end + 30 * minuteMs) }
        let lateBaseline = try #require(UsualSleepDuration.baseline(late, at: Self.t(clock), clock: clock))
        #expect(lateBaseline.nights == 7 && lateBaseline.asleepMs == 7.5 * hourMs)

        // 23:00–07:00 local each night, spanning 8 March: in Pacific time
        // that night is 7 h asleep, the rest 8 h; the median stays 8 h.
        let wallClock = (0...9).map { back -> SleepSession in
            let wake = clock.setTime(clock.addingDays(-back, to: Self.t(clock)), hour: 7)
            let bed = clock.setTime(clock.addingDays(-back - 1, to: Self.t(clock)), hour: 23)
            return SleepSession(id: "healthkit:sleep:sample:w\(back)", start: bed, end: wake)
        }
        let dst = try #require(UsualSleepDuration.baseline(wallClock, at: Self.t(clock), clock: clock))
        #expect(dst.nights == 9 && dst.asleepMs == 8 * hourMs)
        let durations = wallClock.map { ($0.end - $0.start) / hourMs }
        #expect(durations.contains(7) == (zone == "America/Los_Angeles"))
    }

    @Test func theSetupAndSettingsNeverReceiveTheBaseline() throws {
        // Decoding and saving a state with a baseline-worthy history keeps no target.
        let clock = Self.clock("UTC")
        var state = AppState()
        state.sleeps = Self.history([7, 7, 7, 7, 7, 7, 7], t: Self.t(clock), clock: clock)
        let reopened = try JSONDecoder().decode(AppState.self, from: StateMigration.encode(state))
        #expect(reopened.prefs.targetSleep == nil)
        #expect(!String(decoding: try StateMigration.encode(reopened), as: UTF8.self).contains("chosenTargetSleep"))
    }
}
