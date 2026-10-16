import Foundation
import Testing
@testable import AuroraCore

/// Golden cases E1–E9 from docs/research/sleep-and-check-in.md §6. Clock UTC,
/// D = 2026-03-02, times in local time, durations in minutes.
enum SleepGolden {
    static let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
    /// 2026-03-02T00:00:00Z.
    static let d: Millis = 1_772_409_600_000

    /// `day` relative to D (-1 is D-1), at hh:mm local.
    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Millis {
        d + Millis(day) * dayMs + Millis(hour) * hourMs + Millis(minute) * minuteMs
    }

    static func health(_ id: String, _ start: Millis, _ end: Millis) -> SleepSession {
        SleepSession(id: "healthkit:sleep:sample:\(id)", start: start, end: end)
    }

    static func manual(_ id: String, _ start: Millis, _ end: Millis, _ type: SleepType = .sleep) -> SleepSession {
        SleepSession(id: "manual:sleep:\(id)", start: start, end: end, type: type)
    }

    static func minutes(_ ms: Millis) -> Double { ms / minuteMs }
}

@Suite("Sleep episodes: one 90-minute rule")
struct SleepEpisodeTests {
    typealias G = SleepGolden
    let now = SleepGolden.at(0, 20)

    @Test func e1StageSamplesFormOneMainEpisodeWithoutTheAwakeSample() {
        // The awake sample (01:30–01:40) is dropped at import; only asleep values arrive.
        let sessions = [
            G.health("core1", G.at(-1, 23), G.at(-1, 23, 40)),
            G.health("deep", G.at(-1, 23, 40), G.at(0, 0, 20)),
            G.health("core2", G.at(0, 0, 20), G.at(0, 1, 30)),
            G.health("rem", G.at(0, 1, 40), G.at(0, 2, 10)),
            G.health("core3", G.at(0, 2, 10), G.at(0, 6, 50)),
        ]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.count == 1)
        #expect(episodes[0].start == G.at(-1, 23) && episodes[0].end == G.at(0, 6, 50))
        #expect(G.minutes(episodes[0].asleepMs) == 460)
        #expect(episodes[0].kind == .main)
    }

    @Test func e2OverlappingSourcesCountOnce() {
        let sessions = [
            G.health("watch", G.at(-1, 23), G.at(0, 7)),
            G.health("thirdparty", G.at(-1, 22, 45), G.at(0, 6, 30)),
        ]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.count == 1)
        #expect(G.minutes(episodes[0].asleepMs) == 495)
        #expect(episodes[0].kind == .main)
    }

    @Test func e3AWakeGapUnder90MinutesJoinsOneNight() {
        let sessions = [G.health("a", G.at(-1, 23), G.at(0, 2)), G.health("b", G.at(0, 3, 15), G.at(0, 7))]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.count == 1)
        #expect(G.minutes(episodes[0].asleepMs) == 405)
        #expect(G.minutes(episodes[0].spanMs) == 480)
        #expect(episodes[0].kind == .main)
        // The Health import counted this as two nights under the old 30-minute rule.
        #expect(HealthImport.countNights(sessions.map { HealthSleepSample(start: $0.start, end: $0.end) }) == 1)
        // And the chart agrees: one night, one day total.
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: now, clock: G.utc, text: fixtureText)
        #expect(week.recordedNights == 1)
        #expect(week.lastNight.map { G.minutes($0.durationMs) } == 405)
    }

    @Test func e4AGapOfExactly90MinutesSplits() {
        let sessions = [G.health("a", G.at(-1, 23), G.at(0, 2)), G.health("b", G.at(0, 3, 30), G.at(0, 7))]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.count == 2)
        #expect(episodes.map(\.kind) == [.secondary, .main])
        #expect(episodes.map { G.minutes($0.asleepMs) } == [180, 210])
        #expect(SleepEpisodes.asleepByWakeDay(episodes)[G.utc.dayKey(G.d)].map(G.minutes) == 390)
        #expect(HealthImport.countNights(sessions.map { HealthSleepSample(start: $0.start, end: $0.end) }) == 2)
    }

    @Test func e5AShortAfternoonSleepCountsForTheDayButNotLastNight() {
        let sessions = [G.health("night", G.at(-1, 23, 30), G.at(0, 7)), G.health("doze", G.at(0, 14, 10), G.at(0, 14, 35))]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.map(\.kind) == [.main, .short])
        #expect(episodes.map { G.minutes($0.asleepMs) } == [450, 25])
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: now, clock: G.utc, text: fixtureText)
        #expect(week.points.last?.durationMs.map(G.minutes) == 475)
        #expect(week.lastNight.map { G.minutes($0.durationMs) } == 450)
        #expect(week.lastNight?.sessionIDs == ["healthkit:sleep:sample:night"])
    }

    @Test func e7ThePersonsNapLabelWins() {
        let sessions = [G.manual("nap", G.at(0, 13), G.at(0, 16, 30), .nap)]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.map(\.kind) == [.nap])
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: now, clock: G.utc, text: fixtureText)
        #expect(week.lastNight == nil)
        #expect(week.points.last?.durationMs.map(G.minutes) == 210)
    }

    @Test func e8AShortHealthSampleIsNeverMostRecentSleep() {
        let previous = G.health("prev", G.at(-2, 23), G.at(-1, 7))
        let sessions = [previous, G.health("short", G.at(0, 3), G.at(0, 5))]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.map(\.kind) == [.main, .short])
        #expect(G.minutes(episodes[1].asleepMs) == 120)
        let week = SleepModel.presentation(sessions: sessions, targetSleepHours: 8, range: .week, now: now, clock: G.utc, text: fixtureText)
        #expect(week.lastNight?.wakeTime == G.at(-1, 7))
        let summary = RecentSleep.summarize(sessions, targetHours: 8, now: now, clock: G.utc)
        #expect(summary.lastMain?.end == G.at(-1, 7))
    }

    @Test func e9ASessionStillRunningIsLeftOut() {
        let sessions = [G.health("running", G.at(0, 19), G.at(0, 23))]
        #expect(SleepEpisodes.build(sessions, now: now, clock: G.utc).isEmpty)
    }

    @Test func mainSleepTiesGoToTheLaterWake() {
        let sessions = [G.health("a", G.at(-1, 1), G.at(-1, 5)), G.health("b", G.at(-1, 13), G.at(-1, 17))]
        #expect(SleepEpisodes.build(sessions, now: now, clock: G.utc).map(\.kind) == [.secondary, .main])
    }

    @Test func aNapJoinedToANightIsPartOfTheMainSleep() {
        let sessions = [G.manual("nap", G.at(-1, 21), G.at(-1, 22), .nap), G.manual("night", G.at(-1, 22, 45), G.at(0, 7))]
        let episodes = SleepEpisodes.build(sessions, now: now, clock: G.utc)
        #expect(episodes.count == 1 && episodes[0].kind == .main)
        #expect(G.minutes(episodes[0].asleepMs) == 555)
    }

    @Test func inertiaAndEvidenceUseTheSameEpisode() {
        // A 45-minute awakening: one episode, so the wake-up term dates from 07:00.
        let sessions = [G.health("a", G.at(-1, 23), G.at(0, 3)), G.health("b", G.at(0, 3, 45), G.at(0, 7))]
        let t = G.at(0, 7, 30)
        #expect(SleepInertia.minutesSinceLastWake(at: t, sleeps: sessions) == 30)
        let estimate = EnergyEstimate.capture(at: t, doses: [], sleeps: sessions, inputs: EstimateInputs(halfLifeHours: 5, targetSleepHours: 8, clock: G.utc))
        #expect(estimate.evidence.lastWakeAt == G.at(0, 7))
        #expect(estimate.evidence.sleep.allSatisfy { $0.inLatestEpisode })
    }
}
