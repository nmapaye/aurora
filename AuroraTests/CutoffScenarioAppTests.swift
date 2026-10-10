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

    @Test func calculateSetsCaptureLineAndRefreshKeepsIt() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, _) = setup(directory)
        assistant.openCutoff(input: scenario(app), app: app)
        let id = try #require(assistant.pendingMessageID)
        try await Task.sleep(for: .milliseconds(20))
        assistant.calculateCutoff(app: app)
        let calculated = try #require(card(assistant, id))
        #expect(calculated.capturedAt == calculated.cutoff?.capturedAt && calculated.timeZone == calculated.cutoff?.timeZone)
        try await Task.sleep(for: .milliseconds(20))
        assistant.refresh(calculated, app: app)
        #expect(card(assistant, id)?.capturedAt == calculated.capturedAt && card(assistant, id)?.cutoff == calculated.cutoff)
        #expect(card(assistant, assistant.pendingMessageID)!.capturedAt > calculated.capturedAt)
    }

    // MARK: Saves that finish late

    /// Holds each schedule call until the test releases it.
    @MainActor final class GatedScheduler {
        var calls: [CutoffScenario.ReminderContent] = []
        private var waiting: [CheckedContinuation<ReminderService.ScenarioOutcome, Never>] = []
        func schedule(_ content: CutoffScenario.ReminderContent) async -> ReminderService.ScenarioOutcome {
            calls.append(content)
            return await withCheckedContinuation { waiting.append($0) }
        }
        func release(_ outcome: ReminderService.ScenarioOutcome) { waiting.removeFirst().resume(returning: outcome) }
        func waitForCalls(_ count: Int) async {
            for _ in 0..<1000 where calls.count < count { await Task.yield() }
        }
    }

    /// An open, previewed scenario whose Save is suspended in the scheduler.
    private func suspendedSave(_ app: AppModel, _ assistant: AssistantModel, _ gate: GatedScheduler) async -> (UUID, Task<Void, Never>) {
        assistant.openCutoff(input: scenario(app), app: app)
        let id = assistant.pendingMessageID!
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        let task = Task { await assistant.saveCutoffReminder(app: app) }
        await gate.waitForCalls(gate.calls.count + 1)
        return (id, task)
    }

    private func gated(_ directory: URL) -> (AppModel, AssistantModel, GatedScheduler) {
        let (app, assistant, _) = setup(directory)
        let gate = GatedScheduler()
        assistant.scheduleCutoffReminder = { await gate.schedule($0) }
        return (app, assistant, gate)
    }

    @Test(arguments: [ReminderService.ScenarioOutcome.scheduled, .failed]) func closeDuringSaveGetsNoReceiptOrFailure(outcome: ReminderService.ScenarioOutcome) async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, gate) = gated(directory)
        let (id, task) = await suspendedSave(app, assistant, gate)
        #expect(assistant.savingCutoffReminder)
        // Inputs are locked while saving.
        assistant.editCutoff { $0.thresholdMg = "70" }
        #expect(assistant.pendingCutoff?.thresholdMg == "50")
        assistant.discardDraft()
        #expect(!assistant.savingCutoffReminder)
        let messages = assistant.conversation.messages.count
        gate.release(outcome); await task.value
        #expect(assistant.conversation.messages.count == messages && assistant.failure == nil)
        // A reminder iOS accepted stays true of its own closed card.
        #expect(card(assistant, id)?.state == .discarded)
        #expect(card(assistant, id)?.cutoff?.reminder.map { if case .scheduled = $0 { true } else { false } } == (outcome == .scheduled ? true : nil))
    }

    @Test func newerScenarioKeepsItsOwnSaveWhenTheOlderFinishes() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, gate) = gated(directory)
        let (oldID, oldTask) = await suspendedSave(app, assistant, gate)
        // Opening a newer scenario closes the older one and starts its own Save.
        let (newID, newTask) = await suspendedSave(app, assistant, gate)
        #expect(card(assistant, oldID)?.state == .expired && gate.calls.count == 2)
        let newPreview = assistant.cutoffPreview
        // The older Save fails late: nothing about the newer one changes,
        // and its defer can't clear the newer Save's in-flight state.
        gate.release(.failed); await oldTask.value
        #expect(assistant.savingCutoffReminder && assistant.cutoffPreview == newPreview && assistant.failure == nil)
        #expect(card(assistant, oldID)?.cutoff?.reminder == nil && card(assistant, newID)?.cutoff?.reminder == nil)
        // A second tap while the newer Save runs does nothing.
        await assistant.saveCutoffReminder(app: app)
        #expect(gate.calls.count == 2)
        gate.release(.scheduled); await newTask.value
        #expect(!assistant.savingCutoffReminder && assistant.cutoffPreview == nil)
        #expect(assistant.conversation.messages.filter { $0.card?.title == "Scenario reminder scheduled" }.count == 1)
        #expect(assistant.conversation.messages.last?.card?.kind == .receipt)
        if case .scheduled = card(assistant, newID)?.cutoff?.reminder {} else { Issue.record("expected the newer card scheduled") }
    }

    @Test(arguments: [false, true]) func clearOrEraseDuringSaveAddsNothingLate(erase: Bool) async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, gate) = gated(directory)
        await assistant.start(app: app)
        let (_, task) = await suspendedSave(app, assistant, gate)
        if erase { assistant.resetAfterErase() } else { assistant.clearConversation() }
        #expect(!assistant.savingCutoffReminder && assistant.pendingCutoff == nil)
        let after = assistant.conversation
        gate.release(.scheduled); await task.value
        #expect(assistant.conversation == after && assistant.failure == nil)
    }

    @Test func notAllowedExplainsHowToEnable() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let (app, assistant, scheduler) = setup(directory)
        scheduler.outcome = .notAllowed
        assistant.openCutoff(input: scenario(app), app: app)
        assistant.calculateCutoff(app: app)
        assistant.previewCutoffReminder(app: app)
        await assistant.saveCutoffReminder(app: app)
        #expect(assistant.failure == AssistantModel.notAllowedMessage)
        #expect(AssistantModel.notAllowedMessage.contains("Reminders or Settings") && AssistantModel.notAllowedMessage.contains("iOS Settings"))
    }

    @Test func uiTestSchedulerNeedsItsArgument() async throws {
        #expect(AssistantModel.uiTestCutoffScheduler([]) == nil)
        let scheduler = try #require(AssistantModel.uiTestCutoffScheduler(["-AuroraUITestCutoffReminder", "notAllowed"]))
        #expect(await scheduler(.init(title: "", body: "", fireAt: 0)) == .notAllowed)
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
