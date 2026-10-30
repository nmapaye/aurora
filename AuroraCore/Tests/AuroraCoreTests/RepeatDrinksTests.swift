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

    @Test(arguments: zones) func yesterdaysDrinkIsAskedAboutAnHourAfterThatTimeToday(zone: String) throws {
        let clock = clock(zone)
        let sameTime = clock.setTime(Self.base, hour: 9, minute: 30)
        let yesterday = clock.addingDays(-1, to: sameTime)
        let planned = RepeatDrinks.planned(doses: [dose("a", yesterday)], now: clock.setTime(Self.base, hour: 8), clock: clock)
        let prompt = try #require(planned.first)
        #expect(planned.count == 1)
        #expect(prompt.dueAt == sameTime + 60 * minuteMs && prompt.sameTimeAt == sameTime)
        #expect(prompt.expiresAt == sameTime + 4 * hourMs)
        #expect(prompt.id == "repeat:a")
        #expect(RepeatDrinks.question(prompt, text: fixtureText) == "Did you have a Drip around \(fixtureTime(yesterday))?")
        #expect(RepeatDrinks.detail(prompt) == "Yesterday · 95 mg")
        // Not at the usual time: only once the hour has passed.
        #expect(RepeatDrinks.due(planned, conversation: open, now: sameTime, clock: clock).isEmpty)
        #expect(RepeatDrinks.due(planned, conversation: open, now: sameTime + 59 * minuteMs, clock: clock).isEmpty)
        let now = sameTime + 60 * minuteMs
        #expect(RepeatDrinks.due(planned, conversation: open, now: now, clock: clock).map(\.id) == ["repeat:a"])
        let draft = RepeatDrinks.draft(prompt, now: now)
        #expect(draft.mg == "95" && draft.source == "Drip" && draft.timestamp == now)
    }

    @Test func questionsArePastTenseAndNeverCueTheDrink() {
        let at: Millis = Self.base
        func ask(_ source: String?) -> String {
            RepeatDrinks.question(.init(doseID: "a", source: source, mg: 95, yesterdayAt: at, dueAt: at), text: fixtureText)
        }
        #expect(ask("Espresso") == "Did you have an Espresso around \(fixtureTime(at))?")
        #expect(ask("Matcha latte") == "Did you have a Matcha latte around \(fixtureTime(at))?")
        #expect(ask("  ") == "Did you have caffeine around \(fixtureTime(at))?")
        #expect(ask(nil) == "Did you have caffeine around \(fixtureTime(at))?")
        for line in [ask("Drip"), ask(nil), RepeatDrinks.notificationTitle] {
            #expect(CopyRules.violations(in: line).isEmpty)
            for cue in ["again", "usual", "time for", "ready for", "today?"] {
                #expect(!line.lowercased().contains(cue), "\(line) contains \(cue)")
            }
        }
    }

    @Test func theSameWallClockTimeAcrossTheEndOfDaylightTime() throws {
        // Los Angeles leaves daylight time on Sun, Nov 1, 2026: a 25-hour day.
        let clock = clock("America/Los_Angeles")
        let sunday = clock.setTime(1_793_548_800_000, hour: 9, minute: 30) // Nov 1, 9:30 PST
        let monday = clock.addingDays(1, to: clock.setTime(sunday, hour: 12))
        let prompt = try #require(RepeatDrinks.planned(doses: [dose("a", sunday)], now: monday, clock: clock).first)
        #expect(clock.hour(prompt.sameTimeAt) == 9 && clock.hour(prompt.dueAt) == 10)
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
        #expect(RepeatDrinks.due(planned, conversation: open, now: at + hourMs - minuteMs, clock: clock).isEmpty)
        #expect(RepeatDrinks.due(planned, conversation: open, now: at + RepeatDrinks.windowMs - minuteMs, clock: clock).map(\.id) == ["repeat:a"])
        #expect(RepeatDrinks.due(planned, conversation: open, now: at + RepeatDrinks.windowMs, clock: clock).isEmpty)
        var delivered = open; delivered.deliveredSuggestions["repeat:a"] = at
        #expect(RepeatDrinks.due(planned, conversation: delivered, now: at + hourMs, clock: clock).isEmpty)
        var dismissed = open; dismissed.dismissedSuggestions.insert("repeat:a")
        #expect(RepeatDrinks.due(planned, conversation: dismissed, now: at + hourMs, clock: clock).isEmpty)
        var quiet = open; quiet.preferences.quietStartHour = 8; quiet.preferences.quietEndHour = 12
        #expect(RepeatDrinks.due(planned, conversation: quiet, now: at + hourMs, clock: clock).isEmpty)
        #expect(RepeatDrinks.upcoming(planned, conversation: quiet, now: at - hourMs, clock: clock).isEmpty)
        #expect(RepeatDrinks.upcoming(planned, conversation: open, now: at - hourMs, clock: clock).map(\.id) == ["repeat:a"])
        #expect(RepeatDrinks.upcoming(planned, conversation: open, now: at + minuteMs, clock: clock).map(\.id) == ["repeat:a"])
        #expect(RepeatDrinks.upcoming(planned, conversation: open, now: at + hourMs, clock: clock).isEmpty)
    }

    @Test(arguments: zones) func nothingAtOrAfterTheirCutoffTime(zone: String) {
        let clock = clock(zone)
        let y = clock.addingDays(-1, to: clock.startOfDay(Self.base))
        let doses = [dose("a", y + 9 * hourMs), dose("b", y + 13 * hourMs + 30 * minuteMs, 60, "Tea"), dose("c", y + 14 * hourMs, 40, "Cola")]
        let morning = clock.setTime(Self.base, hour: 8)
        // A 15:00 cutoff: the 14:00 tea would be asked at 15:00, so it isn't.
        #expect(RepeatDrinks.planned(doses: doses, now: morning, clock: clock, cutoffHour: 15).map(\.doseID) == ["a", "b"])
        #expect(RepeatDrinks.planned(doses: doses, now: morning, clock: clock).map(\.doseID) == ["a", "b", "c"])
        let planned = RepeatDrinks.planned(doses: doses, now: morning, clock: clock, cutoffHour: 15)
        let afterCutoff = clock.setTime(Self.base, hour: 15)
        #expect(RepeatDrinks.due(planned, conversation: open, now: afterCutoff - minuteMs, clock: clock, cutoffHour: 15).map(\.doseID) == ["b"])
        #expect(RepeatDrinks.due(planned, conversation: open, now: afterCutoff, clock: clock, cutoffHour: 15).isEmpty)
    }

    @Test(arguments: zones) func oneSilentBatchWithoutAmounts(zone: String) throws {
        let clock = clock(zone)
        let y = clock.addingDays(-1, to: clock.startOfDay(Self.base))
        let doses = [dose("a", y + 8 * hourMs), dose("b", y + 10 * hourMs, 70, "Matcha"), dose("c", y + 15 * hourMs, 40, "")]
        let planned = RepeatDrinks.planned(doses: doses, now: clock.setTime(Self.base, hour: 7), clock: clock)
        let upcoming = RepeatDrinks.upcoming(planned, conversation: open, now: clock.setTime(Self.base, hour: 7), clock: clock)
        let batch = try #require(RepeatDrinks.batch(upcoming, clock: clock))
        // At the latest due time; the 8:00 drink's window closed by then.
        #expect(batch.fireAt == clock.setTime(Self.base, hour: 16))
        #expect(batch.prompts.map(\.doseID) == ["c"])
        #expect(batch.identifier.hasPrefix(RepeatDrinks.notificationPrefix))
        #expect(RepeatDrinks.notificationBody(batch, text: fixtureText) == "Caffeine · around \(fixtureTime(y + 15 * hourMs)).")

        let morning = try #require(RepeatDrinks.batch(Array(upcoming.prefix(2)), clock: clock))
        #expect(morning.fireAt == clock.setTime(Self.base, hour: 11) && morning.prompts.map(\.doseID) == ["a", "b"])
        let body = RepeatDrinks.notificationBody(morning, text: fixtureText)
        #expect(body == "Drip · around \(fixtureTime(y + 8 * hourMs)).\nMatcha · around \(fixtureTime(y + 10 * hourMs)).")
        #expect(!body.contains("mg") && !RepeatDrinks.notificationTitle.contains("mg"))
        #expect(RepeatDrinks.batch([], clock: clock) == nil)
    }

    @Test(arguments: zones) func notificationsPauseAfterFiveUnansweredDays(zone: String) {
        let clock = clock(zone)
        let today = clock.setTime(Self.base, hour: 12)
        func day(_ offset: Int) -> Millis { clock.addingDays(-offset, to: today) }
        func prompt(_ id: String, _ dayOffset: Int) -> RepeatDrinks.Prompt {
            let due = clock.setTime(day(dayOffset), hour: 10)
            return .init(doseID: id, source: "Drip", mg: 95, yesterdayAt: due - dayMs - hourMs, dueAt: due)
        }
        var log = RepeatDrinks.Engagement()
        // Four ignored days, then a day without follow-ups, then today.
        for offset in [6, 5, 4, 3] { log.recordOffered([prompt("d\(offset)", offset)], now: day(offset), clock: clock) }
        #expect(log.unansweredStreak(doses: [], now: today, clock: clock) == 4)
        #expect(!log.isPaused(doses: [], now: today, clock: clock))
        log.recordOffered([prompt("d1", 1)], now: day(1), clock: clock)
        #expect(log.isPaused(doses: [], now: today, clock: clock))
        // Today's open follow-up doesn't count until it's answered or over.
        log.recordOffered([prompt("d0", 0)], now: today, clock: clock)
        #expect(log.unansweredStreak(doses: [], now: today, clock: clock) == 5)

        // A drink of that kind logged around yesterday's time answered it.
        let logged = [dose("mine", clock.setTime(day(1), hour: 9, minute: 15), 95, "Espresso")]
        #expect(log.unansweredStreak(doses: logged, now: today, clock: clock) == 0)
        // "Log it" today answers today.
        var answered = log
        answered.recordAnswered(now: today, clock: clock)
        #expect(!answered.isPaused(doses: [], now: today, clock: clock))
        // Nothing older than two weeks is kept.
        log.recordOffered([prompt("late", 0)], now: clock.addingDays(20, to: today), clock: clock)
        #expect(log.days.count == 1)
    }

    @Test(arguments: zones) func aNotificationCountsOnceItsTimeHasPassed(zone: String) throws {
        let clock = clock(zone)
        let now = clock.setTime(Self.base, hour: 8)
        let y = clock.addingDays(-1, to: clock.startOfDay(now))
        let planned = RepeatDrinks.planned(doses: [dose("a", y + 9 * hourMs)], now: now, clock: clock)
        var log = RepeatDrinks.Engagement(scheduled: try #require(RepeatDrinks.batch(planned, clock: clock)))
        log.settle(now: now, clock: clock)
        #expect(log.days.isEmpty && log.scheduled != nil)
        log.settle(now: clock.setTime(now, hour: 10), clock: clock)
        #expect(log.scheduled == nil && log.days.map(\.prompts) == [planned])
        // Shown in the conversation as well: still one follow-up that day.
        log.recordOffered(planned, now: clock.setTime(now, hour: 11), clock: clock)
        #expect(log.days.count == 1 && log.days[0].prompts.count == 1)
    }

    @Test func oneAuroraNotificationADayWithTheBriefingFirst() {
        var p = AssistantPreferences()
        p.quietStartHour = 22; p.quietEndHour = 6
        #expect(NotificationBudget.auroraInitiatedPerDay == 1)
        #expect(NotificationBudget.allowed([.drinkFollowUps, .morningBriefing]) == [.morningBriefing])
        #expect(NotificationBudget.allowed([.drinkFollowUps]) == [.drinkFollowUps])
        // No briefing notification: follow-ups may notify.
        #expect(NotificationBudget.followUpsMayNotify(p))
        p.proactive = true
        #expect(NotificationBudget.followUpsMayNotify(p))
        p.morningBriefing = true
        #expect(NotificationBudget.briefingNotifies(p) && !NotificationBudget.followUpsMayNotify(p))
        // A briefing hour inside quiet hours never notifies, so it takes no slot.
        p.briefingHour = 23
        #expect(!NotificationBudget.briefingNotifies(p) && NotificationBudget.followUpsMayNotify(p))
    }

    @Test func conversationsFromOlderBuildsDecodeWithoutEngagement() throws {
        var state = ConversationState()
        state.repeatDrinkEngagement = nil
        let written = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!written.contains("repeatDrinkEngagement"))
        #expect(try JSONDecoder().decode(ConversationState.self, from: Data(written.utf8)) == state)
        state.repeatDrinkEngagement = .init(days: [.init(dayStart: 0, prompts: [], answered: true)])
        #expect(try JSONDecoder().decode(ConversationState.self, from: JSONEncoder().encode(state)) == state)
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
