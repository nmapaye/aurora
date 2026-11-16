import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// Follow-up chat in the app (CPO plan §c/§e): a question opens Estimated
/// Active Caffeine, routed in code with Apple Intelligence on or off, and
/// writes 0 doses and 0 Health samples. Log This Drink opens the confirm
/// card; only its Save records, whatever the save switch says.
@MainActor
@Suite struct CaffeineAtTimeAppTests {
    let root: URL
    let health = ScriptedHealth()
    let model: AppModel
    let assistant: AssistantModel

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-caffeine-at-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("Support/Aurora", isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        model = AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            health: health,
            makeStore: { StateStore(directory: directory) },
            legacy: { LegacyImport(documents: docs) }
        )
        model.load()
        _ = model.completeOnboarding()
        _ = await model.setHealthChoice(.writeCaffeine, enabled: true)
        assistant = AssistantModel(
            calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!),
            makeStore: { ConversationStore(directory: directory) }
        )
        await assistant.start(app: model)
    }

    private func settleHealth() async {
        await model.waitForHealthExports()
        await model.healthSync.runPendingActions()
    }

    private func expectNothingWritten() async {
        #expect(model.state.doses.isEmpty)
        await settleHealth()
        #expect(health.savedSyncIdentifiers.isEmpty)
    }

    private var followUp: ConversationMessage? { assistant.conversation.messages.last { $0.card?.kind == .caffeineAtTime } }

    @Test(arguments: [true, false]) func aQuestionWritesNothing(intelligenceOff: Bool) async throws {
        assistant.intelligenceOffOverride = intelligenceOff
        assistant.savePolicySetting = .instant
        assistant.send("if I drink 126mg now how much at 11pm", app: model)
        let message = try #require(followUp)
        let state = try #require(message.card?.caffeineAtTime)
        #expect(message.card?.title == CaffeineAtTime.title)
        #expect(state.result?.rows.count == 1)
        #expect(state.drink?.asked?.label == CaffeineAtTime.notLoggedLabel)
        #expect(assistant.pendingDraft == nil && !assistant.processing)
        await expectNothingWritten()
    }

    @Test func aChipAnswersABareHourAndStillWritesNothing() async throws {
        assistant.intelligenceOffOverride = true
        assistant.send("how much caffeine is active at 9", app: model)
        let message = try #require(followUp)
        let choice = try #require(message.card?.caffeineAtTime?.choices.last)
        assistant.chooseCaffeineAtTime(message.id, choice, app: model)
        let state = try #require(followUp?.card?.caffeineAtTime)
        #expect(state.result?.rows.count == 1)
        await expectNothingWritten()
    }

    @Test func logThisDrinkOpensTheConfirmCardEvenWithInstantSaves() async throws {
        assistant.intelligenceOffOverride = true
        assistant.savePolicySetting = .instant
        assistant.send("if I drink 126mg now how much at 11pm", app: model)
        let message = try #require(followUp)
        assistant.logCaffeineAtTimeDrink(message.id, app: model)
        #expect(assistant.pendingDraft?.mg == "126")
        #expect(assistant.conversation.messages.last?.card?.kind == .caffeineDraft)
        await expectNothingWritten()
        assistant.saveDose(app: model)
        #expect(model.state.doses.count == 1)
    }

    @Test func aCorrectionKeepsATypedAmount() async throws {
        assistant.intelligenceOffOverride = true
        assistant.send("if I drink 126mg now how much at 11pm", app: model)
        assistant.send("Actually a caramel latte", app: model)
        let state = try #require(followUp?.card?.caffeineAtTime)
        #expect(state.drink?.mg == 126)
        #expect(state.note == CaffeineAtTimeCard.amountKeptLine(126))
        #expect(assistant.pendingDraft == nil)
        await expectNothingWritten()
    }

    @Test func aPastTenseQuestionShowsTheCapabilityList() async throws {
        assistant.intelligenceOffOverride = true
        assistant.send("how much caffeine did I have at 3pm", app: model)
        #expect(assistant.conversation.messages.last?.card?.kind == .capabilities)
        await expectNothingWritten()
    }

    @Test func anUnusableAmountAsksAgainAndOpensNothing() async throws {
        assistant.intelligenceOffOverride = true
        assistant.send("how much caffeine at 11pm if I drank -126mg at 5pm", app: model)
        #expect(assistant.conversation.messages.last?.text == CaffeineQuestion.amountClarification)
        #expect(followUp == nil && assistant.pendingDraft == nil)
        await expectNothingWritten()
    }
}
