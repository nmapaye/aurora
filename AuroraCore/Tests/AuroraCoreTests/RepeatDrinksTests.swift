import Foundation
import Testing
@testable import AuroraCore

struct RepeatDrinksTests {
    static let zones = ["UTC", "America/Los_Angeles"]
    /// Thu, Oct 8, 2026, noon UTC.
    static let base: Millis = 1_791_460_800_000

    func clock(_ zone: String) -> LocalClock { LocalClock(timeZone: TimeZone(identifier: zone)!) }
    func dose(_ id: String, _ at: Millis, _ mg: Double = 95, _ source: String? = "Drip") -> Dose {
        Dose(id: id, timestamp: at, mg: mg, source: source)
    }
    var open: ConversationState {
        var state = ConversationState()
        state.preferences.quietStartHour = 22; state.preferences.quietEndHour = 6
        return state
    }

    @Test(arguments: zones) func yesterdaysDrinkIsAskedAboutAtTheSameTimeToday(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 10)
        let yesterday = clock.addingDays(-1, to: clock.setTime(Self.base, hour: 9, minute: 30))
        let planned = RepeatDrinks.planned(doses: [dose("a", yesterday)], now: now, clock: clock)
        let prompt = try #require(planned.first)
        #expect(planned.count == 1)
        #expect(prompt.dueAt == clock.setTime(Self.base, hour: 9, minute: 30))
        #expect(prompt.id == "repeat:a")
        #expect(RepeatDrinks.question(prompt, text: fixtureText) == "Had your \(fixtureTime(yesterday)) Drip today?")
        #expect(RepeatDrinks.detail(prompt) == "Yesterday · 95 mg")
        #expect(RepeatDrinks.due(planned, conversation: open, now: now, clock: clock).map(\.id) == ["repeat:a"])
        let draft = RepeatDrinks.draft(prompt, now: now)
        #expect(draft.mg == "95" && draft.source == "Drip" && draft.timestamp == now)
    }

    @Test func theSameWallClockTimeAcrossTheEndOfDaylightTime() throws {
        // Los Angeles leaves daylight time on Sun, Nov 1, 2026: a 25-hour day.
        let clock = clock("America/Los_Angeles")
        let sunday = clock.setTime(1_793_548_800_000, hour: 9, minute: 30) // Nov 1, 9:30 PST
        let monday = clock.addingDays(1, to: clock.setTime(sunday, hour: 12))
        let prompt = try #require(RepeatDrinks.planned(doses: [dose("a", sunday)], now: monday, clock: clock).first)
        #expect(clock.hour(prompt.dueAt) == 9)
        #expect(clock.dayKey(prompt.dueAt) == clock.dayKey(monday))
    }

    @Test(arguments: zones) func onlyYesterdaysDrinksEnteredInAurora(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 18)
        let y = clock.addingDays(-1, to: clock.startOfDay(now))
        let doses = [
            dose("demo:sample", y + 9 * hourMs),
            dose("healthkit:caffeine:other-app", y + 10 * hourMs),
            dose("zero", y + 11 * hourMs, 0),
            dose("two-days-ago", clock.addingDays(-1, to: y) + 9 * hourMs),
            dose("today", clock.startOfDay(now) + 8 * hourMs, 95, "Matcha"),
            dose("kept", y + 14 * hourMs, 60, "Matcha latte"),
        ]
        #expect(RepeatDrinks.planned(doses: doses, now: now, clock: clock).map(\.doseID) == ["kept"])
    }

    @Test(arguments: zones) func aDrinkAlreadyLoggedAroundThatTimeAnswersIt(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 12)
        let at = clock.setTime(Self.base, hour: 9, minute: 30)
        let yesterday = dose("y", clock.addingDays(-1, to: at), 95, "Drip")
        // An espresso at 10:15 today is coffee too, within 90 minutes.
        #expect(RepeatDrinks.planned(doses: [yesterday, dose("t", at + 45 * minuteMs, 60, "Espresso")], now: now, clock: clock).isEmpty)
        // Tea doesn't answer a coffee question; coffee three hours later doesn't either.
        #expect(RepeatDrinks.planned(doses: [yesterday, dose("t", at, 30, "Tea")], now: now, clock: clock).count == 1)
        #expect(RepeatDrinks.planned(doses: [yesterday, dose("t", at + 3 * hourMs, 95, "Drip")], now: now, clock: clock).count == 1)
    }

    @Test(arguments: zones) func closeDrinksAskOnceAndAtMostThreeADay(zone: String) {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 23)
        let y = clock.addingDays(-1, to: clock.startOfDay(now))
        let doses = [
            dose("a", y + 8 * hourMs), dose("a2", y + 8 * hourMs + 30 * minuteMs),
            dose("b", y + 11 * hourMs), dose("c", y + 14 * hourMs, 30, "Tea"),
            dose("d", y + 17 * hourMs), dose("e", y + 19 * hourMs),
        ]
        #expect(RepeatDrinks.planned(doses: doses, now: now, clock: clock).map(\.doseID) == ["a", "b", "c"])
    }

    @Test(arguments: zones) func shownOncePerDrinkAndNeverInQuietHoursOrAfterTheWindow(zone: String) {
        let clock = clock(zone)
        let at = clock.setTime(Self.base, hour: 9)
        let planned = RepeatDrinks.planned(doses: [dose("a", clock.addingDays(-1, to: at))], now: at + hourMs, clock: clock)
        #expect(RepeatDrinks.due(planned, conversation: open, now: at - minuteMs, clock: clock).isEmpty)
        #expect(RepeatDrinks.due(planned, conversation: open, now: at + RepeatDrinks.windowMs, clock: clock).isEmpty)
        var delivered = open; delivered.deliveredSuggestions["repeat:a"] = at
        #expect(RepeatDrinks.due(planned, conversation: delivered, now: at + hourMs, clock: clock).isEmpty)
        var dismissed = open; dismissed.dismissedSuggestions.insert("repeat:a")
        #expect(RepeatDrinks.due(planned, conversation: dismissed, now: at + hourMs, clock: clock).isEmpty)
        var quiet = open; quiet.preferences.quietStartHour = 8; quiet.preferences.quietEndHour = 12
        #expect(RepeatDrinks.due(planned, conversation: quiet, now: at + hourMs, clock: clock).isEmpty)
        #expect(RepeatDrinks.upcoming(planned, conversation: quiet, now: at - hourMs, clock: clock).isEmpty)
        #expect(RepeatDrinks.upcoming(planned, conversation: open, now: at - hourMs, clock: clock).map(\.id) == ["repeat:a"])
        #expect(RepeatDrinks.upcoming(planned, conversation: open, now: at + minuteMs, clock: clock).isEmpty)
    }

    @Test func followUpsDontUseTheSuggestionAllowance() {
        let clock = clock("UTC")
        let now = clock.setTime(Self.base, hour: 12)
        var state = open; state.preferences.proactive = true
        state.deliveredSuggestions = ["repeat:a": now - hourMs, "repeat:b": now - 2 * hourMs, "repeat:c": now - 3 * hourMs]
        #expect(ProactivePolicy.canDeliver(key: "brief:today", state: state, now: now, clock: clock))
        state.deliveredSuggestions["calendar:x"] = now - hourMs; state.deliveredSuggestions["sleep:y"] = now - hourMs
        #expect(!ProactivePolicy.canDeliver(key: "brief:today", state: state, now: now, clock: clock))
    }

    @Test func prefsFromOlderBuildsDecodeWithFollowUpsOff() throws {
        let data = try JSONEncoder().encode(Prefs.defaults)
        let decoded = try JSONDecoder().decode(Prefs.self, from: data)
        #expect(decoded.repeatDrinks == nil)
        var on = Prefs.defaults; on.repeatDrinks = .init(enabled: true, notify: false)
        #expect(try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(on)) == on)
    }
}
