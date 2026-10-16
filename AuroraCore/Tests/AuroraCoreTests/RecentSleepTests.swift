import Foundation
import Testing
@testable import AuroraCore

/// Golden cases S1–S6 and U1–U4 from docs/research/sleep-and-check-in.md §6.
@Suite("Recent sleep summary and usual timing")
struct RecentSleepTests {
    typealias G = SleepGolden

    /// A main sleep waking on D+`day` at 07:00 after `hours` asleep.
    static func night(_ day: Int, hours: Double) -> SleepSession {
        let end = G.at(day, 7)
        return G.health("n\(day)", end - hours * hourMs, end)
    }

    /// S1: 7.0, 6.5, nil, 8.0, 5.5, 7.5, 6.0 h on D-6 … D.
    static func s1(eightHourNight: Double = 8) -> [SleepSession] {
        zip(-6...0, [7.0, 6.5, nil, eightHourNight, 5.5, 7.5, 6.0]).compactMap { day, hours in hours.map { night(day, hours: $0) } }
    }

    @Test func s1RecordedNightsOnlyAndAShortfallAgainstTheTarget() {
        let summary = RecentSleep.summarize(Self.s1(), targetHours: 8, now: G.at(0, 12), clock: G.utc)
        #expect(summary.nights.count == 7)
        #expect(summary.nights.map { $0.asleepMs.map(G.minutes) } == [420, 390, nil, 480, 330, 450, 360])
        #expect(summary.recordedNights == 6)
        #expect(summary.meanAsleepMs.map(G.minutes) == 405)
        #expect(summary.shortfallMs.map(G.minutes) == 450)
        #expect(summary.shortfallUnavailable == nil)
        #expect(summary.lastMain?.end == G.at(0, 7))
        #expect(summary.msSinceMainWake == 5 * hourMs)
    }

    @Test func s2ASurplusNightOffsetsOnlyWithinTheSignedSum() {
        let summary = RecentSleep.summarize(Self.s1(eightHourNight: 9), targetHours: 8, now: G.at(0, 12), clock: G.utc)
        #expect(summary.meanAsleepMs.map(G.minutes) == 415)
        #expect(summary.shortfallMs.map(G.minutes) == 390)
    }

    @Test func s2bTheShortfallIsFlooredAtZero() {
        let sessions = (-6...0).map { Self.night($0, hours: 9) }
        let summary = RecentSleep.summarize(sessions, targetHours: 8, now: G.at(0, 12), clock: G.utc)
        #expect(summary.shortfallMs == 0)
        #expect(RecentSleep.describe(summary, targetHours: 8).contains("At or over your 8h target"))
    }

    @Test func s3FourNightsShowAMeanButNoShortfall() {
        let sessions = [-3, -2, -1, 0].map { Self.night($0, hours: 7) }
        let summary = RecentSleep.summarize(sessions, targetHours: 8, now: G.at(0, 12), clock: G.utc)
        #expect(summary.recordedNights == 4)
        #expect(summary.meanAsleepMs.map(G.minutes) == 420)
        #expect(summary.shortfallMs == nil)
        #expect(summary.shortfallUnavailable == .tooFewNights(recorded: 4, required: 5))
        #expect(!RecentSleep.describe(summary, targetHours: 8).contains("target"))
    }

    @Test func s4NoTargetMeansNoShortfallAndNoInventedReference() {
        let summary = RecentSleep.summarize(Self.s1(), targetHours: nil, now: G.at(0, 12), clock: G.utc)
        #expect(summary.recordedNights == 6)
        #expect(summary.shortfallMs == nil)
        #expect(summary.shortfallUnavailable == .noTarget)
        #expect(RecentSleep.describe(summary, targetHours: nil) == "Recorded sleep, last 7 days: 6 of 7 nights, average 6h 45m.")
    }

    @Test func s5Last24And48HoursIncludeNaps() {
        let sessions = [
            G.health("a", G.at(-2, 23, 30), G.at(-1, 6, 30)),
            G.health("b", G.at(-1, 23), G.at(0, 7)),
            G.manual("nap", G.at(0, 14), G.at(0, 14, 30), .nap),
        ]
        let summary = RecentSleep.summarize(sessions, targetHours: 8, now: G.at(0, 18), clock: G.utc)
        #expect(G.minutes(summary.asleepLast24hMs) == 510)
        #expect(G.minutes(summary.asleepLast48hMs) == 930)
        // The nap counts toward the day's total, but the night is the main sleep.
        #expect(summary.nights.last?.asleepMs.map(G.minutes) == 510)
        #expect(summary.lastMain.map { G.minutes($0.asleepMs) } == 480)
    }

    @Test func s6TheWindowEndsYesterdayUntilTodayHasAMainSleep() {
        let sessions = [Self.night(-1, hours: 8)]
        let summary = RecentSleep.summarize(sessions, targetHours: 8, now: G.at(0, 6), clock: G.utc)
        #expect(summary.nights.last?.dayKey == G.utc.dayKey(G.at(-1, 12)))
        #expect(summary.nights.first?.dayKey == G.utc.dayKey(G.at(-7, 12)))
        #expect(summary.recordedNights == 1)
    }

    @Test func aNapAloneIsNotARecordedNight() {
        let sessions = [G.manual("nap", G.at(0, 13), G.at(0, 16, 30), .nap)]
        let summary = RecentSleep.summarize(sessions, targetHours: 8, now: G.at(0, 18), clock: G.utc)
        #expect(summary.recordedNights == 0 && summary.meanAsleepMs == nil && summary.lastMain == nil)
        #expect(G.minutes(summary.asleepLast24hMs) == 210)
    }

    @Test func summariesHoldInPacificTimeAcrossDST() {
        // Nights waking 07:00 local either side of the 8 March 2026 change.
        let pacific = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let base = pacific.setTime(1_773_000_000_000, hour: 7)
        let sessions = (0..<7).map { offset -> SleepSession in
            let end = pacific.addingDays(-offset, to: base)
            return SleepSession(id: "healthkit:sleep:sample:p\(offset)", start: end - 7 * hourMs, end: end)
        }
        let summary = RecentSleep.summarize(sessions, targetHours: 7.5, now: base + hourMs, clock: pacific)
        #expect(summary.recordedNights == 7)
        #expect(summary.meanAsleepMs == 7 * hourMs)
        #expect(summary.shortfallMs == 7 * 30 * minuteMs)
        let timing = UsualSleepTiming.compute(sessions, now: base + hourMs, clock: pacific)
        #expect(timing?.wakeMinute == 7 * 60)
        #expect(timing?.startMinute == 0)
    }

    // MARK: Usual timing

    static func span(_ day: Int, startMinute: Int, hours: Double = 8) -> SleepSession {
        let start = G.at(day - 1, 0) + Millis(startMinute) * minuteMs
        return G.health("u\(day)", start, start + hours * hourMs)
    }

    @Test func u1MidpointAndWakeFromEightMainSleeps() {
        // 4× 23:00–07:00, 3× 00:30–08:30, 1× 22:30–06:30.
        let starts = [23 * 60, 23 * 60, 23 * 60, 23 * 60, 24 * 60 + 30, 24 * 60 + 30, 24 * 60 + 30, 22 * 60 + 30]
        let sessions = starts.enumerated().map { Self.span(-$0.offset, startMinute: $0.element) }
        let timing = UsualSleepTiming.compute(sessions, now: G.at(0, 12), clock: G.utc)
        #expect(timing?.midpointMinute == 3 * 60)
        #expect(timing?.wakeMinute == 7 * 60)
        #expect(timing?.nights == 8)
        #expect(timing?.middle80Midpoint == nil)
        #expect(timing.map { UsualSleepTiming.describe($0) { "\($0 / 60):\(String(format: "%02d", $0 % 60))" } } == "Usual midpoint 3:00 · wake 7:00 · 8 nights")
    }

    @Test func u2MidpointsAcrossMidnightUseTheCircularMedian() {
        // Midpoints 23:30, 23:40, 23:50, 00:00, 00:10, 00:20, 00:30.
        let midpoints = [23 * 60 + 30, 23 * 60 + 40, 23 * 60 + 50, 24 * 60, 24 * 60 + 10, 24 * 60 + 20, 24 * 60 + 30]
        let sessions = midpoints.enumerated().map { Self.span(-$0.offset, startMinute: $0.element - 4 * 60) }
        let timing = UsualSleepTiming.compute(sessions, now: G.at(0, 12), clock: G.utc)
        #expect(timing?.midpointMinute == 0)
        // What a naive linear median of the clock minutes would say.
        let naive = midpoints.map { $0 % 1440 }.sorted()[midpoints.count / 2]
        #expect(naive == 30)
        #expect(UsualSleepTiming.circularMedian(midpoints.map { $0 % 1440 }) == 0)
    }

    @Test func u3SixMainSleepsAreNotEnough() {
        let sessions = (0..<6).map { Self.span(-$0, startMinute: 23 * 60) }
        #expect(UsualSleepTiming.compute(sessions, now: G.at(0, 12), clock: G.utc) == nil)
        #expect(UsualSleepTiming.gatheringText(nights: 6) == "6 of 7 main sleeps in the last 14 days. Usual timing appears at 7.")
    }

    @Test func u4ADaytimeSleeperStaysInTheDaytime() {
        // Midpoints 12:00 … 13:00 for someone working nights.
        let midpoints = [12 * 60, 12 * 60 + 10, 12 * 60 + 20, 12 * 60 + 30, 12 * 60 + 40, 12 * 60 + 50, 13 * 60]
        let sessions = midpoints.enumerated().map { Self.span(-$0.offset - 1, startMinute: 24 * 60 + $0.element - 4 * 60) }
        let timing = UsualSleepTiming.compute(sessions, now: G.at(0, 23), clock: G.utc)
        #expect(timing?.midpointMinute == 12 * 60 + 30)
        // The fixed +12 h shift `usualNight` used put such a bedtime half a day away.
        #expect(UsualSleepTiming.circularMedian(midpoints) == 12 * 60 + 30)
    }

    @Test func theSpreadNeedsFourteenMainSleepsInThirtyDays() {
        let thirteen = (0..<13).map { Self.span(-$0, startMinute: 23 * 60 + ($0 % 3) * 20) }
        #expect(UsualSleepTiming.compute(thirteen, now: G.at(0, 12), clock: G.utc)?.middle80Midpoint == nil)
        let fourteen = (0..<14).map { Self.span(-$0 * 2, startMinute: 23 * 60 + ($0 % 3) * 20) }
        let timing = UsualSleepTiming.compute(fourteen, now: G.at(0, 12), clock: G.utc)
        // Seven of them fall in the last 14 days; all fourteen in 30.
        #expect(timing?.nights == 7)
        #expect(timing?.middle80Midpoint == MinuteOfDayRange(lower: 3 * 60, upper: 3 * 60 + 40))
    }

    @Test func usualNightDraftKeepsBedtimesAcrossMidnightTogether() {
        // Manual nights starting 23:30, 00:30, 00:00: the circular median is 00:00.
        let now = G.at(0, 12)
        let starts = [23 * 60 + 30, 24 * 60 + 30, 24 * 60]
        let sessions = starts.enumerated().map { offset, minute -> SleepSession in
            let start = G.at(-offset - 2, 0) + Millis(minute) * minuteMs
            return G.manual("m\(offset)", start, start + 7 * hourMs)
        }
        let draft = AssistantPlanner.usualNight(sessions, now: now, clock: G.utc)
        #expect(draft.map { G.utc.hour($0.start) } == 0)
    }
}
