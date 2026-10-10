import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// Cutoff scenarios in the conversation. Scheduling is injected: nothing
/// here reaches the notification center or asks for permission.
@MainActor
@Suite struct CutoffScenarioAppTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func calendars() -> CalendarService { CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!) }

    /// Records schedule calls and answers with `outcome`.
    @MainActor final class Scheduler {
        var calls: [CutoffScenario.ReminderContent] = []
        var outcome = ReminderService.ScenarioOutcome.scheduled
    }

    private func setup(_ directory: URL) -> (AppModel, AssistantModel, Scheduler) {
        let app = AppModel(makeStore: { StateStore(directory: directory.appendingPathComponent("records")) }, legacy: { nil })
        app.load()
        let assistant = AssistantModel(calendars: calendars(), makeStore: { ConversationStore(directory: directory) })
        let scheduler = Scheduler()
        assistant.scheduleCutoffReminder = { content in
            scheduler.calls.append(content)
            await Task.yield()
            return scheduler.outcome
        }
        return (app, assistant, scheduler)
    }

    /// A bedtime ten hours ahead, 50 mg threshold and a 100 mg hypothetical:
    /// the latest time is five hours before bedtime, still in the future.
    private func scenario(_ app: AppModel) -> CutoffScenario.Input {
        app.tick()
        return .init(bedtime: .init(app.now + 10 * hourMs, timeZone: app.clock.timeZone), bedtimeOccurrence: .first, thresholdMg: "50", drinkMg: "100")
    }

    private func card(_ assistant: AssistantModel, _ id: UUID?) -> AssistantCard? {
        assistant.conversation.messages.first { $0.id == id }?.card
    }

    @Test func opensWithEmptyInputsAndRecordsNothing() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, scheduler) = setup(directory)
        await assistant.handle(.cutoffScenario, input: "Cutoff scenario", app: app)
        #expect(assistant.pendingCutoff == CutoffScenario.Input())
        let opened = card(assistant, assistant.pendingMessageID)
        #expect(opened?.kind == .cutoffScenario && opened?.cutoff?.result.problems == [.missingBedtime, .missingThreshold])
        assistant.editCutoff { $0 = scenario(app) }
        assistant.calculateCutoff(app: app)
        #expect(app.state.doses.isEmpty && scheduler.calls.isEmpty)
        #expect(app.state.prefs.notifyCutoff == Prefs.defaults.notifyCutoff && app.state.prefs.cutoffHour == Prefs.defaults.cutoffHour)
    }

    @Test func calculatedResultIsFrozenAndRefreshMakesANewSnapshot() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, _) = setup(directory)
        assistant.openCutoff(input: scenario(app), app: app)
        assistant.calculateCutoff(app: app)
        let first = try #require(assistant.pendingMessageID)
        let frozen = try #require(card(assistant, first)?.cutoff)
        guard case .feasible = frozen.result.latest else { Issue.record("expected a time"); return }
        _ = app.addCustomDose(.init(mg: "80", source: "Drip", timestamp: app.now - minuteMs, note: ""))
        #expect(card(assistant, first)?.cutoff == frozen)
        assistant.refresh(try #require(card(assistant, first)), app: app)
        #expect(card(assistant, first)?.state == .expired && card(assistant, first)?.cutoff == frozen)
        let renewed = try #require(card(assistant, assistant.pendingMessageID)?.cutoff)
        #expect(assistant.pendingMessageID != first && renewed.input == frozen.input)
        #expect(renewed.result.basis != frozen.result.basis && renewed.capturedAt >= frozen.capturedAt)
    }

    @Test func savesOnceAfterPreviewAndLeavesDailyReminderAlone() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, scheduler) = setup(directory)
        assistant.openCutoff(input: scenario(app), app: app)
        let id = try #require(assistant.pendingMessageID)
        // Save without a preview does nothing.
        await assistant.saveCutoffReminder(app: app)
        #expect(scheduler.calls.isEmpty)
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        let preview = try #require(assistant.cutoffPreview)
        #expect(preview.content.body.contains("not a safety limit"))
        let messages = assistant.conversation.messages.count
        async let a: Void = assistant.saveCutoffReminder(app: app)
        async let b: Void = assistant.saveCutoffReminder(app: app)
        _ = await (a, b)
        await assistant.saveCutoffReminder(app: app)
        #expect(scheduler.calls == [preview.content])
        #expect(assistant.conversation.messages.count == messages + 1)
        #expect(assistant.conversation.messages.last?.card?.title == "Scenario reminder scheduled")
        if case .scheduled(let fireAt, _) = card(assistant, id)?.cutoff?.reminder { #expect(fireAt == preview.content.fireAt) }
        else { Issue.record("expected a scheduled outcome on the card") }
        #expect(assistant.cutoffPreview == nil && app.state.doses.isEmpty)
        #expect(app.state.prefs.notifyCutoff == Prefs.defaults.notifyCutoff && app.state.prefs.cutoffHour == Prefs.defaults.cutoffHour)
    }

    @Test(arguments: [ReminderService.ScenarioOutcome.failed, .notAllowed]) func failedSaveShowsNoReceipt(outcome: ReminderService.ScenarioOutcome) async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, scheduler) = setup(directory)
        scheduler.outcome = outcome
        assistant.openCutoff(input: scenario(app), app: app)
        let id = assistant.pendingMessageID
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        let messages = assistant.conversation.messages.count
        await assistant.saveCutoffReminder(app: app)
        #expect(scheduler.calls.count == 1)
        #expect(assistant.conversation.messages.count == messages)
        #expect(!assistant.conversation.messages.contains { $0.card?.kind == .receipt })
        #expect(card(assistant, id)?.cutoff?.reminder == (outcome == .failed ? .failed : .notAllowed))
        #expect(assistant.failure != nil)
        // The preview stays for an explicit retry.
        #expect(assistant.cutoffPreview != nil)
    }

    @Test func changedRecordsOrInputsRequireANewPreview() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, scheduler) = setup(directory)
        assistant.openCutoff(input: scenario(app), app: app)
        let id = assistant.pendingMessageID
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        _ = app.addCustomDose(.init(mg: "30", source: "Tea", timestamp: app.now - minuteMs, note: ""))
        await assistant.saveCutoffReminder(app: app)
        #expect(scheduler.calls.isEmpty && assistant.cutoffPreview == nil)
        #expect(card(assistant, id)?.cutoff?.reminder == .needsNewPreview)
        // An edit closes a preview before Save can use it.
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        #expect(assistant.cutoffPreview != nil)
        assistant.editCutoff { $0.thresholdMg = "60" }
        #expect(assistant.cutoffPreview == nil)
        await assistant.saveCutoffReminder(app: app)
        #expect(scheduler.calls.isEmpty)
        // Inputs differ from the frozen result: no preview until Calculate.
        assistant.previewCutoffReminder(app: app)
        #expect(assistant.cutoffPreview == nil)
    }

    @Test func closedAndRelaunchedScenariosCannotAct() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, scheduler) = setup(directory)
        await assistant.start(app: app)
        assistant.openCutoff(input: scenario(app), app: app)
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        assistant.discardDraft()
        await assistant.saveCutoffReminder(app: app)
        #expect(scheduler.calls.isEmpty && assistant.cutoffPreview == nil && assistant.pendingCutoff == nil)

        // A ready scenario saved before relaunch comes back expired, result kept.
        assistant.openCutoff(input: scenario(app), app: app)
        assistant.calculateCutoff(app: app)
        let id = assistant.pendingMessageID
        let frozen = card(assistant, id)?.cutoff
        let (relaunchedApp, relaunched, again) = setup(directory)
        await relaunched.start(app: relaunchedApp)
        #expect(card(relaunched, id)?.state == .expired && card(relaunched, id)?.cutoff == frozen)
        #expect(relaunched.pendingCutoff == nil)
        relaunched.previewCutoffReminder(app: relaunchedApp)
        await relaunched.saveCutoffReminder(app: relaunchedApp)
        #expect(again.calls.isEmpty && relaunched.cutoffPreview == nil)
    }

    @Test func savedConversationWithScenarioDecodesAndOldOneStillLoads() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var state = ConversationState()
        state.messages = [.init(text: "Old", intent: .weeklyTrends, card: .init(kind: .trends, capturedAt: 1, title: "Old"))]
        try store.save(state)
        #expect(try store.load() == state)
        var scenarioCard = AssistantCards.make(.cutoffScenario, state: AppState(), now: 1_791_481_200_000, clock: .init(timeZone: TimeZone(identifier: "UTC")!), text: .current)
        scenarioCard.cutoff?.reminder = .failed
        state.messages.append(.init(text: "Scenario", intent: .cutoffScenario, card: scenarioCard))
        try store.save(state)
        #expect(try store.load() == state)
    }
}
