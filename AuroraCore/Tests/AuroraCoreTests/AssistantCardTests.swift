import Foundation
import Testing
@testable import AuroraCore

@Suite struct AssistantCardTests {
    let now: Millis = 1_791_481_200_000
    let clock = LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    var text: DateText { .localized(locale: Locale(identifier: "en_US"), timeZone: clock.timeZone) }

    @Test(arguments: AssistantCard.Kind.allCases) func everyCardRoundTrips(kind: AssistantCard.Kind) throws {
        let card = AssistantCards.make(kind, state: AppState(), now: now, clock: clock, text: text)
        #expect(!card.title.isEmpty)
        #expect(card.timeZone == clock.timeZone.identifier)
        let data = try JSONEncoder().encode(card)
        #expect(try JSONDecoder().decode(AssistantCard.self, from: data) == card)
        #expect(CopyRules.violations(in: card.summary).isEmpty)
    }
    @Test func noRecordIsNotZeroAndNoInventedCause() {
        let card = AssistantCards.make(.energy, state: AppState(), now: now, clock: clock, text: text)
        #expect(card.metrics.first { $0.id == "caffeine" }?.value == "No record")
        #expect(card.metrics.first { $0.id == "sleep" }?.value == "No record")
        #expect(card.metrics.first { $0.id == "alertness" }?.value == "Needs sleep")
        // No cause is offered for how someone feels, in the summary or metrics.
        let text = ([card.summary] + card.metrics.map { "\($0.value) \($0.detail ?? "")" }).joined(separator: " ").lowercased()
        #expect(!text.contains("because") && !text.contains("due to") && !text.contains("caused"))
    }
    @Test(arguments: [AssistantCard.Kind.energy, .briefing]) func energySurfacesNeedMainSleep(kind: AssistantCard.Kind) throws {
        var state = AppState()
        state.sleeps = [
            .init(id: "manual:sleep:nap:a", start: now - 8 * hourMs, end: now - 6 * hourMs),
            .init(id: "manual:sleep:nap:b", start: now - 4 * hourMs, end: now - 2 * hourMs),
        ]

        let card = AssistantCards.make(kind, state: state, now: now, clock: clock, text: text)
        let alertness = try #require(card.metrics.first { $0.id == "alertness" })
        #expect(alertness.value == "Needs sleep")
        #expect(alertness.missing)
        #expect(alertness.detail.contains("No sleep of at least 3 hours ended in the 18 hours before"))
    }
    @Test func snapshotStaysFixedWhenRecordsChange() {
        var state = AppState()
        let before = AssistantCards.make(.energy, state: state, now: now, clock: clock, text: text)
        state.doses = [.init(id: "a", timestamp: now - hourMs, mg: 80)]
        let after = AssistantCards.make(.energy, state: state, now: now + minuteMs, clock: clock, text: text)
        #expect(before.metrics.first { $0.id == "caffeine" }?.value == "No record")
        #expect(after.metrics.first { $0.id == "caffeine" }?.value == "80 mg")
        #expect(before.capturedAt != after.capturedAt)
    }
    @Test func trendsPreserveMissingDaysAndComparisonGate() {
        var state = AppState(); state.doses = [.init(id: "demo:a", timestamp: now - hourMs, mg: 60)]
        let card = AssistantCards.make(.trends, state: state, now: now, clock: clock, text: text)
        #expect(card.series.count == 6)
        let caffeine = card.series.first { $0.metric == "Caffeine" && $0.days == 7 }!
        #expect(caffeine.points.filter { $0.value == nil }.count == 6)
        #expect(caffeine.points.contains { $0.sample })
        #expect(caffeine.comparison.contains("recorded"))
        #expect(card.series.first { $0.metric == "Reaction" }?.points.allSatisfy { $0.value == nil } == true)
    }
    @Test func historyProtectsSamplesAndHealthAndTracksCorrections() {
        var state = AppState()
        state.sleeps = [.init(id: "healthkit:sleep:1:2", start: now - 9 * hourMs, end: now - hourMs), .init(id: "manual:sleep:1", start: now - 8 * hourMs, end: now - hourMs)]
        state.doses = [.init(id: "demo:coffee", timestamp: now - hourMs, mg: 80)]
        let before = AssistantCards.make(.history, state: state, now: now, clock: clock, text: text)
        #expect(before.records.first { $0.id.hasPrefix("healthkit:") }?.editable == false)
        #expect(before.records.first { $0.id.hasPrefix("manual:") }?.editable == true)
        #expect(before.records.first { $0.id.hasPrefix("demo:") }?.editable == false)
        state.sleeps[1].note = "Corrected note"
        let after = AssistantCards.make(.history, state: state, now: now, clock: clock, text: text)
        #expect(before.records.first { $0.id == "manual:sleep:1" } != after.records.first { $0.id == "manual:sleep:1" })
    }
    @Test func newCapabilitiesRouteWithoutAModel() {
        #expect(AssistantPlanner.explicitIntent("Export my records") == .exports)
        #expect(AssistantPlanner.explicitIntent("Morning briefing") == .briefing)
        #expect(AssistantPlanner.explicitIntent("Reminders") == .reminders)
    }
    @Test func sleepExportPreservesSourceAndQuotes() {
        let csv = Export.sleepSessionsCSV([.init(id: "manual:sleep:1", start: now - 8 * hourMs, end: now, note: "A \"note\"")], clock: clock)
        #expect(csv.contains("duration_hours") && csv.contains("Manual") && csv.contains("\"\"note\"\""))
    }
}
