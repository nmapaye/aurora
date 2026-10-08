import Foundation
import Testing
@testable import AuroraCore

@Suite struct AssistantTests {
    let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    let now: Millis = 1_791_481_200_000

    @Test(arguments: [
        ("Had my usual coffee", AssistantIntent.logCaffeine),
        ("Why am I tired?", .explainEnergy), ("Show this week", .weeklyTrends),
        ("Rework my afternoon", .calendar), ("log sleep", .logSleep),
        ("reaction test", .reactionTest), ("how much coffee should I drink?", .unsupported),
        ("don't log coffee", .unsupported), ("cancel my appointment", .unsupported)
    ]) func supportedRequests(input: String, expected: AssistantIntent) {
        #expect(AssistantPlanner.explicitIntent(input) == expected)
    }
    @Test func modelCannotReturnAnExecutableAction() {
        #expect(AssistantPlanner.modelIntent("delete all records") == .unsupported)
        #expect(AssistantPlanner.modelIntent("calendar; cancel appointment") == .unsupported)
        #expect(AssistantPlanner.modelIntent(" logSleep\n") == .logSleep)
    }
    @Test func unknownUsualDoesNotInventAmount() {
        let draft = AssistantPlanner.caffeineDraft("Had my usual coffee", doses: [], now: now)
        #expect(draft.mg.isEmpty)
        #expect(CaffeineLog.validate(draft, now: now) != .valid)
    }
    @Test func usualExcludesSamplesFutureAndOldRecords() {
        let entries = [Dose(id: "a", timestamp: now - hourMs, mg: 120, source: "Cold Brew"), Dose(id: "b", timestamp: now - dayMs, mg: 120, source: "Cold Brew")]
        let excluded = (0..<10).map { Dose(id: "demo:\($0)", timestamp: now - hourMs, mg: 999) }
            + (0..<10).map { Dose(id: "future:\($0)", timestamp: now + dayMs, mg: 900) }
            + (0..<10).map { Dose(id: "old:\($0)", timestamp: now - 40 * dayMs, mg: 800) }
        let draft = AssistantPlanner.caffeineDraft("Had my usual coffee", doses: entries + excluded, now: now)
        #expect(draft.mg == "120" && draft.source == "Cold Brew")
    }
    @Test func explicitAmountOverridesUsualAndInvalidAmountStaysInvalid() {
        let draft = AssistantPlanner.caffeineDraft("I had 2000 mg tea", doses: [], now: now)
        #expect(draft.mg == "2000")
        #expect(CaffeineLog.validate(draft, now: now) != .valid)
    }
    @Test func missingRecordsAreNotMeasurements() {
        let text = AssistantPlanner.energyExplanation(state: AppState(), now: now, clock: clock)
        #expect(text.contains("No record") && text.contains("unavailable"))
        #expect(!text.contains("0 mg recorded"))
        #expect(CopyRules.violations(in: text).isEmpty)
    }
    @Test func localSettingsRoundTripWithoutKeys() throws {
        let state = ConversationState()
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(ConversationState.self, from: data) == state)
        #expect(!String(decoding: data, as: UTF8.self).contains("apiKey"))
    }
    @Test func proactiveRequiresOptInAndRespectsQuietHours() {
        var state = ConversationState()
        let midday = clock.setTime(now, hour: 12)
        #expect(!ProactivePolicy.canDeliver(key: "a", state: state, now: midday, clock: clock))
        state.preferences.proactive = true
        #expect(ProactivePolicy.canDeliver(key: "a", state: state, now: midday, clock: clock))
        for hour in [21, 23, 0, 7] {
            #expect(!ProactivePolicy.canDeliver(key: "a", state: state, now: clock.setTime(now, hour: hour), clock: clock))
        }
    }
    @Test func suggestionsDeduplicateAndResetAtLocalMidnight() {
        var state = ConversationState(); state.preferences.proactive = true
        let midday = clock.setTime(now, hour: 12)
        state.deliveredSuggestions = ["a": midday, "b": midday]
        #expect(!ProactivePolicy.canDeliver(key: "c", state: state, now: midday, clock: clock))
        #expect(ProactivePolicy.canDeliver(key: "c", state: state, now: clock.addingDays(1, to: midday), clock: clock))
        #expect(!ProactivePolicy.canDeliver(key: "a", state: state, now: clock.addingDays(1, to: midday), clock: clock))
        state.dismissedSuggestions.insert("c")
        #expect(!ProactivePolicy.canDeliver(key: "c", state: state, now: clock.addingDays(1, to: midday), clock: clock))
    }
    @Test func quietHoursHandleNonOvernightInterval() {
        var state = ConversationState(); state.preferences.proactive = true
        state.preferences.quietStartHour = 12; state.preferences.quietEndHour = 15
        #expect(!ProactivePolicy.canDeliver(key: "a", state: state, now: clock.setTime(now, hour: 13), clock: clock))
        #expect(ProactivePolicy.canDeliver(key: "a", state: state, now: clock.setTime(now, hour: 16), clock: clock))
    }
    @Test func usualNightIsHistoricalAndExcludesNapsSamplesAndHealth() throws {
        let today = clock.startOfDay(now)
        let sessions = (2...4).map { offset in
            let end = clock.setTime(clock.addingDays(-offset, to: today), hour: 7)
            return SleepSession(id: "manual:sleep:\(offset)", start: end - 8 * hourMs, end: end)
        }
        let sample = SleepSession(id: "demo:sleep", start: now - 5 * hourMs, end: now)
        let nap = SleepSession(id: "manual:sleep:nap", start: now - hourMs, end: now, type: .nap)
        let draft = try #require(AssistantPlanner.usualNight(sessions + [sample, nap], now: clock.setTime(today, hour: 10), clock: clock))
        #expect(draft.end - draft.start == 8 * hourMs)
        #expect(clock.hour(draft.start) == 23)
        #expect(draft.end <= clock.setTime(today, hour: 10))
        #expect(AssistantPlanner.usualNight([sample, nap], now: now, clock: clock) == nil)
    }
    @Test func invalidLocalModelLabelsAreNotGuessed() {
        #expect(AssistantPlanner.modelIntent("The answer is logCaffeine") == .unsupported)
        #expect(AssistantPlanner.modelIntent("{\"intent\":\"calendar\"}") == .unsupported)
    }
    @Test func malformedAmountsAndCorrectionsStayReviewable() {
        for text in ["I had -100 mg tea", "I had 95.5 mg tea", "I had 80 mg and 120 mg coffee"] {
            let draft = AssistantPlanner.caffeineDraft(text, doses: [], now: now)
            #expect(CaffeineLog.validate(draft, now: now) != .valid)
        }
        #expect(AssistantPlanner.explicitIntent("I had steak") == nil)
        #expect(AssistantPlanner.explicitIntent("I had coffee and log sleep") == .unsupported)
        let previous = CustomDoseDraft(mg: "80", source: "Tea", timestamp: now, note: "")
        let corrected = AssistantPlanner.correctedDraft(previous, input: "Actually 120 mg yesterday at 8am", now: now, clock: clock)
        #expect(corrected?.mg == "120")
        #expect(corrected.map { clock.hour($0.timestamp) } == 8)
        #expect(corrected.map { clock.dayKey($0.timestamp) } == clock.dayKey(clock.addingDays(-1, to: now)))
    }
}

@Suite struct CalendarApprovalTests {
    let now = Date(timeIntervalSince1970: 1_791_481_200)
    func event(provider: CalendarProviderID = .apple) -> Commitment {
        .init(id: "event", calendarID: "calendar", provider: provider, title: "Study", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), timeZone: "America/Los_Angeles", revision: "v1", canMove: true, recurring: false)
    }
    @Test(arguments: [CalendarProviderID.apple, .google]) func requiresApprovalAndFreshRevision(provider: CalendarProviderID) throws {
        let original = event(provider: provider)
        let change = CalendarChange(original: original, newStart: original.start.addingTimeInterval(3600), newEnd: original.end.addingTimeInterval(3600))
        #expect(throws: CalendarActionError.approvalRequired) { try CalendarActionValidator.validate(change, current: original, approvedID: nil, now: now, others: []) }
        var stale = original; stale.revision = "v2"
        #expect(throws: CalendarActionError.stale) { try CalendarActionValidator.validate(change, current: stale, approvedID: change.id, now: now, others: []) }
        try CalendarActionValidator.validate(change, current: original, approvedID: change.id, now: now, others: [])
    }
    @Test func readOnlyAndConflictsAreRejected() {
        var original = event(); original.canMove = false
        let change = CalendarChange(original: original, newStart: original.start, newEnd: original.end)
        #expect(throws: CalendarActionError.readOnly) { try CalendarActionValidator.validate(change, current: original, approvedID: change.id, now: now, others: []) }
        original.canMove = true
        var conflict = original; conflict.id = "other"
        let move = CalendarChange(original: original, newStart: original.start, newEnd: original.end)
        #expect(throws: CalendarActionError.conflict) { try CalendarActionValidator.validate(move, current: original, approvedID: move.id, now: now, others: [conflict]) }
    }
    @Test func pastAndDurationChangesAreRejected() {
        let original = event()
        let change = CalendarChange(original: original, newStart: now.addingTimeInterval(-10), newEnd: original.end)
        #expect(throws: CalendarActionError.invalidTime) { try CalendarActionValidator.validate(change, current: original, approvedID: change.id, now: now, others: []) }
    }
    @Test func proposalPreservesDurationAndAvoidsFixedCommitments() throws {
        let original = event(); var fixed = original; fixed.id = "fixed"; fixed.start = original.end; fixed.end = original.end.addingTimeInterval(3600); fixed.canMove = false
        let proposed = try #require(CalendarActionValidator.proposedMove(original, among: [original, fixed], now: now, calendar: .current))
        #expect(proposed.newStart >= fixed.end)
        #expect(proposed.newEnd.timeIntervalSince(proposed.newStart) == original.end.timeIntervalSince(original.start))
    }
    @Test func readOnlyGetsNoProposal() {
        var original = event(); original.canMove = false
        #expect(CalendarActionValidator.proposedMove(original, among: [], now: now, calendar: .current) == nil)
    }
}
