import Foundation
import Testing
@testable import AuroraCore

struct WakeReminderTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    /// Thu, Oct 8, 2026, noon UTC.
    static let base: Millis = 1_791_460_800_000

    func clock(_ zone: String) -> LocalClock { LocalClock(timeZone: TimeZone(identifier: zone)!) }
    func settings(_ offsets: [Int] = [60, 300], usual: Int = 8 * 60) -> WakeReminderSettings {
        WakeReminderSettings(enabled: true, offsetsMinutes: offsets, usualWakeMinutes: usual)
    }
    func sleep(_ id: String = "healthkit:sleep:a", end: Millis, hours: Double = 7, type: SleepType = .sleep) -> SleepSession {
        SleepSession(id: id, start: end - hours * hourMs, end: end, type: type)
    }

    @Test(arguments: zones) func recordedWakePlansEachOffsetFromTheActualWake(zone: String) {
        let clock = clock(zone)
        let wake = clock.setTime(Self.base, hour: 7, minute: 42)
        let now = wake + 10 * minuteMs
        let plan = WakeReminders.plan(settings: settings(), cutoffHour: 16, sleeps: [sleep(end: wake)], now: now, clock: clock, text: fixtureText)
        let today = plan.filter { $0.id.contains(clock.dayKey(now)) }
        #expect(today.map(\.fireAt) == [wake + 60 * minuteMs, wake + 300 * minuteMs])
        #expect(today.allSatisfy { $0.basis == .recordedWake(wake) })
        #expect(today.first?.body == "1h after waking · woke at \(fixtureTime(wake))")
    }

    @Test(arguments: zones) func noRecordedWakeFallsBackToUsualTime(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 6)
        let usual = clock.setTime(now, hour: 8)
        let plan = WakeReminders.plan(settings: settings(), cutoffHour: 16, sleeps: [], now: now, clock: clock, text: fixtureText)
        let today = plan.filter { $0.id.contains(clock.dayKey(now)) }
        #expect(today.map(\.fireAt) == [usual + hourMs, usual + 5 * hourMs])
        #expect(today.first?.body == "1h after your usual \(fixtureTime(usual)) wake time")
    }

    @Test(arguments: zones) func tomorrowIsAlwaysScheduledFromTheUsualTime(zone: String) {
        let clock = clock(zone)
        let wake = clock.setTime(Self.base, hour: 7)
        let now = clock.setTime(Self.base, hour: 20)
        let plan = WakeReminders.plan(settings: settings([60]), cutoffHour: 16, sleeps: [sleep(end: wake)], now: now, clock: clock, text: fixtureText)
        let tomorrow = clock.addingDays(1, to: clock.startOfDay(now))
        #expect(plan.count == 1)
        #expect(plan[0].fireAt == clock.setTime(tomorrow, hour: 9))
        #expect(plan[0].id == "wake-reminder-\(clock.dayKey(tomorrow))-60")
    }

    @Test(arguments: zones) func nothingAtOrAfterTheCutoff(zone: String) {
        let clock = clock(zone)
        let wake = clock.setTime(Self.base, hour: 10)
        let now = wake + minuteMs
        let plan = WakeReminders.plan(settings: settings([60, 360]), cutoffHour: 16, sleeps: [sleep(end: wake)], now: now, clock: clock, text: fixtureText)
        // 11:00 stays; 16:00 equals the cutoff and is dropped.
        #expect(plan.filter { $0.id.contains(clock.dayKey(now)) }.map(\.offsetMinutes) == [60])
        // A half-hour cutoff is honored to the minute.
        let half = WakeReminders.plan(settings: settings([330]), cutoffHour: 15.5, sleeps: [sleep(end: wake)], now: now, clock: clock, text: fixtureText)
        #expect(half.filter { $0.id.contains(clock.dayKey(now)) }.isEmpty)
    }

    @Test(arguments: zones) func lateWakeDeliveryFiresSoonWithinGraceOtherwiseSkips(zone: String) {
        let clock = clock(zone)
        let wake = clock.setTime(Self.base, hour: 7)
        // The wake-up reached Aurora 80 minutes later: the 60-minute reminder is 20 minutes late.
        let now = wake + 80 * minuteMs
        let plan = WakeReminders.plan(settings: settings([30, 60, 120]), cutoffHour: 16, sleeps: [sleep(end: wake)], now: now, clock: clock, text: fixtureText)
        let today = plan.filter { $0.id.contains(clock.dayKey(now)) }
        #expect(today.map(\.offsetMinutes) == [60, 120])
        #expect(today[0].fireAt == now + minuteMs)
        #expect(today[1].fireAt == wake + 120 * minuteMs)
    }

    @Test(arguments: zones) func pastFallbackTimesAreNeverFiredLate(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 9, minute: 10)
        let plan = WakeReminders.plan(settings: settings([60]), cutoffHour: 16, sleeps: [], now: now, clock: clock, text: fixtureText)
        #expect(plan.filter { $0.id.contains(clock.dayKey(now)) }.isEmpty)
    }

    @Test(arguments: zones) func deliveredRemindersAreNotRepeated(zone: String) {
        let clock = clock(zone)
        let wake = clock.setTime(Self.base, hour: 7)
        let now = wake + 70 * minuteMs
        let delivered: Set = ["wake-reminder-\(clock.dayKey(now))-60"]
        let plan = WakeReminders.plan(settings: settings([60]), cutoffHour: 16, sleeps: [sleep(end: wake)], now: now, clock: clock, text: fixtureText, delivered: delivered)
        #expect(plan.filter { $0.id.contains(clock.dayKey(now)) }.isEmpty)
    }

    @Test(arguments: zones) func nightWakingsNapsAndSampleDataDontCount(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 6)
        let sleeps = [
            sleep("healthkit:sleep:night", end: clock.setTime(Self.base, hour: 3, minute: 30), hours: 4),
            sleep("manual:sleep:nap", end: clock.setTime(Self.base, hour: 5, minute: 30), hours: 1, type: .nap),
            sleep("demo:sleep:1", end: clock.setTime(Self.base, hour: 5, minute: 45)),
        ]
        #expect(WakeReminders.recordedWake(sleeps: sleeps, usualWakeMinutes: 8 * 60, now: now, clock: clock) == nil)
        let real = clock.setTime(Self.base, hour: 5, minute: 50)
        #expect(WakeReminders.recordedWake(sleeps: sleeps + [sleep(end: real)], usualWakeMinutes: 8 * 60, now: now, clock: clock) == real)
    }

    @Test func dstMorningKeepsWallClockFallback() {
        // Sun, Nov 1, 2026: clocks fall back at 2:00 in Los Angeles.
        let clock = clock("America/Los_Angeles")
        let now = clock.setTime(1_793_563_200_000, hour: 5)
        let plan = WakeReminders.plan(settings: settings([60]), cutoffHour: 16, sleeps: [], now: now, clock: clock, text: fixtureText)
        #expect(clock.hour(plan[0].fireAt) == 9)
    }

    @Test func disabledOrEmptyPlansNothingAndSettingsNormalize() {
        let clock = clock("UTC")
        let now = clock.setTime(Self.base, hour: 6)
        var off = settings(); off.enabled = false
        #expect(WakeReminders.plan(settings: off, cutoffHour: 16, sleeps: [], now: now, clock: clock, text: fixtureText).isEmpty)
        #expect(WakeReminders.plan(settings: settings([]), cutoffHour: 16, sleeps: [], now: now, clock: clock, text: fixtureText).isEmpty)
        let normalized = WakeReminderSettings(enabled: true, offsetsMinutes: [300, 5, 60, 60, 900, 90, 120, 30], usualWakeMinutes: 2000).normalized()
        #expect(normalized.offsetsMinutes == [30, 60, 90, 120])
        #expect(normalized.usualWakeMinutes == 24 * 60 - 1)
    }

    @Test func copyIsTheirsAndPassesCopyRules() {
        let clock = clock("UTC")
        let wake = clock.setTime(Self.base, hour: 7)
        for reminder in WakeReminders.plan(settings: settings([45, 90, 240]), cutoffHour: 23, sleeps: [sleep(end: wake)], now: wake, clock: clock, text: fixtureText) {
            #expect(CopyRules.violations(in: reminder.title + " " + reminder.body).isEmpty)
            #expect(!reminder.body.localizedCaseInsensitiveContains("should"))
        }
        #expect(WakeReminders.offsetText(45) == "45m")
        #expect(WakeReminders.offsetText(90) == "1h 30m")
        #expect(WakeReminders.offsetText(120) == "2h")
    }

    @Test func savedNonPresetOffsetStaysVisibleInTheEditor() {
        #expect(!WakeReminders.presetOffsets.contains(90))
        #expect(WakeReminders.editorOffsets(saved: []) == WakeReminders.presetOffsets)
        #expect(WakeReminders.editorOffsets(saved: [60]) == WakeReminders.presetOffsets)
        // An offset saved by an older build still gets a chip, so it can be turned off.
        #expect(WakeReminders.editorOffsets(saved: [90, 60]) == [30, 60, 90, 120, 180, 240, 300, 360])
        #expect(WakeReminders.editorOffsets(saved: [5, 900]) == WakeReminders.presetOffsets)
        // A saved 90 is still kept and planned; nothing migrates it away.
        #expect(settings([90]).normalized().offsetsMinutes == [90])
    }

    @Test func olderPrefsDecodeWithoutWakeReminders() throws {
        let prefs = try JSONDecoder().decode(Prefs.self, from: Data(#"{"halfLife":5,"targetSleep":8,"dailyLimitMg":400,"cutoffHour":16,"notifyCutoff":false}"#.utf8))
        #expect(prefs.wakeReminders == nil)
        #expect(!String(decoding: try JSONEncoder().encode(Prefs.defaults), as: UTF8.self).contains("wakeReminders"))
    }

    @Test func reminderTimesJoinTheSameOnEveryPlatform() {
        #expect(SetupTranscript.englishList([]) == "")
        #expect(SetupTranscript.englishList(["1h"]) == "1h")
        #expect(SetupTranscript.englishList(["1h", "5h"]) == "1h and 5h")
        #expect(SetupTranscript.englishList(["1h", "3h", "5h"]) == "1h, 3h, and 5h")
    }

    @Test func setupAsksAfterCalendarAndRecordsTheRealChoice() {
        #expect(SetupStep.calendar.next == .wakeReminders)
        #expect(SetupStep.wakeReminders.next == .finish)
        var state = AppState()
        state.prefs.wakeReminders = WakeReminderSettings(enabled: true, offsetsMinutes: [300, 60], usualWakeMinutes: 420)
        #expect(SetupTranscript.reply(.wakeReminders, .answered, state: state, healthAvailable: true, calendarsChosen: false) == .person("1h and 5h after waking"))
        state.prefs.wakeReminders?.enabled = false
        #expect(SetupTranscript.reply(.wakeReminders, .answered, state: state, healthAvailable: true, calendarsChosen: false) == .person("Not now"))
        #expect(CopyRules.violations(in: SetupCopy.question(.wakeReminders, modelAvailable: true)).isEmpty)
    }
}
