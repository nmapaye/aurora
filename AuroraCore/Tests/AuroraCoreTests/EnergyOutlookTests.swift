import Foundation
import Testing
@testable import AuroraCore

struct EnergyOutlookTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    /// Thu, Oct 8, 2026, noon UTC.
    static let base: Millis = 1_791_460_800_000
    func clock(_ zone: String) -> LocalClock { LocalClock(timeZone: TimeZone(identifier: zone)!) }

    /// Nights from 23:00 to 7:00 for `days` days before `now`'s day, plus last night.
    func nights(_ days: Int, now: Millis, clock: LocalClock, hours: Double = 8) -> [SleepSession] {
        (0...days).map { back in
            let wake = clock.setTime(clock.addingDays(-back, to: now), hour: 7)
            return SleepSession(id: "manual:sleep:\(back)", start: wake - hours * hourMs, end: wake)
        }
    }

    @Test(arguments: zones) func findsTodaysHighAndLowWithinWakingHours(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 9)
        var state = AppState()
        state.sleeps = nights(0, now: now, clock: clock)
        let outlook = EnergyOutlook.make(state: state, now: now, clock: clock)
        let peak = try! #require(outlook.peak)
        let dayStart = clock.startOfDay(now)
        #expect(peak.start >= clock.setTime(dayStart, hour: EnergyOutlook.dayStartHour))
        #expect(peak.end <= clock.setTime(dayStart, hour: EnergyOutlook.dayEndHour) + EnergyProjection.stepMs)
        #expect(peak.start < peak.end)
        if let low = outlook.low { #expect(low.score + EnergyOutlook.windowTolerance < peak.score) }
    }

    @Test(arguments: zones) func noSleepMeansNoOutlook(zone: String) {
        let clock = clock(zone)
        let outlook = EnergyOutlook.make(state: AppState(), now: clock.setTime(Self.base, hour: 9), clock: clock)
        #expect(outlook.isEmpty)
        #expect(outlook.lines(text: fixtureText).isEmpty)
    }

    @Test(arguments: zones) func comparisonNeedsFourRecentDays(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 14)
        var state = AppState()
        state.sleeps = nights(2, now: now, clock: clock)
        #expect(EnergyOutlook.make(state: state, now: now, clock: clock).comparison == nil)
        state.sleeps = nights(7, now: now, clock: clock)
        let outlook = EnergyOutlook.make(state: state, now: now, clock: clock)
        #expect(outlook.comparedDays >= EnergyOutlook.minimumComparedDays)
        #expect(outlook.comparison == .similar)
    }

    @Test(arguments: zones) func shortNightTodayReadsLowerThanThePastWeek(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 14)
        var state = AppState()
        state.sleeps = nights(7, now: now, clock: clock).map { $0.id == "manual:sleep:0" ? SleepSession(id: $0.id, start: $0.end - 3 * hourMs, end: $0.end) : $0 }
        #expect(EnergyOutlook.make(state: state, now: now, clock: clock).comparison == .lower)
    }

    @Test func linesDescribeTheModelAndPassCopyRules() {
        let outlook = EnergyOutlook(
            peak: .init(start: 0, end: 7_200_000, score: 70), low: .init(start: 10_800_000, end: 14_400_000, score: 40),
            comparison: .higher, comparedDays: 6, includesSample: false
        )
        let lines = outlook.lines(text: fixtureText)
        #expect(lines == ["Highest around T0 – T7200000", "Lowest around T10800000 – T14400000", "Higher than your past week at this time"])
        for line in lines { #expect(CopyRules.violations(in: line).isEmpty) }
    }

    @Test func snapshotsKeepTheOutlookAndOlderOnesDecodeWithout() throws {
        let clock = clock("UTC")
        let now = clock.setTime(Self.base, hour: 9)
        var state = AppState()
        state.sleeps = nights(0, now: now, clock: clock)
        let snapshot = EnergySnapshot.capture(state: state, now: now, clock: clock, includeProjection: false)
        #expect(snapshot.outlook?.peak != nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        json.removeValue(forKey: "outlook")
        let older = try JSONDecoder().decode(EnergySnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(older.outlook == nil)
    }
}
