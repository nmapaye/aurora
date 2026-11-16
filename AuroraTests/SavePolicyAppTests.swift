import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// The save switch, both settings (CPO, Nov 16). Confirm (default): 0 doses
/// and no Health sample before Save. Instant: exactly one dose and its
/// Health sample, and Undo removes exactly that entry and deletes only its
/// sample. Only fully specified typed entries and exact repeat-drink copies
/// are instant; defaults, database amounts and shortcuts always confirm.
@MainActor
@Suite struct SavePolicyAppTests {
    let root: URL
    let health = ScriptedHealth()
    let model: AppModel
    let assistant: AssistantModel

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-save-policy-\(UUID().uuidString)", isDirectory: true)
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
        assistant.intelligenceOffOverride = true
    }

    private func settleHealth() async {
        await model.waitForHealthExports()
        await model.healthSync.runPendingActions()
    }
    private func own(_ dose: Dose) -> String { HealthOrigin.syncIdentifier(forDoseID: dose.id) }

    private func expectNothingWritten() async {
        #expect(model.state.doses.isEmpty)
        await settleHealth()
        #expect(health.savedSyncIdentifiers.isEmpty)
    }

    /// Instant: one dose, its sample, a receipt; Undo removes it and deletes only its sample.
    private func expectInstantThenUndo() async throws {
        #expect(model.state.doses.count == 1)
        let dose = try #require(model.state.doses.first)
        await settleHealth()
        #expect(health.savedSyncIdentifiers == [own(dose)])
        #expect(assistant.pendingDraft == nil)
        let receipt = try #require(assistant.conversation.messages.last { $0.card?.kind == .receipt })
        #expect(receipt.card?.title == "Caffeine saved" && receipt.card?.recordID == dose.id)
        assistant.undoReceipt(receipt, app: model)
        #expect(model.state.doses.isEmpty)
        await settleHealth()
        #expect(health.deletedSyncIdentifiers == [own(dose)])
    }

    @Test func defaultSettingIsConfirm() { #expect(assistant.savePolicySetting == .confirm) }

    // Typed entries.

    @Test func confirmTypedEntryWritesNothingBeforeSave() async throws {
        assistant.send("espresso 64mg", app: model)
        #expect(assistant.pendingDraft?.mg == "64")
        await expectNothingWritten()
        assistant.saveDose(app: model)
        try await expectInstantThenUndo()
    }

    @Test func instantTypedEntryWithItsOwnMgSavesOnceWithUndo() async throws {
        assistant.savePolicySetting = .instant
        assistant.send("espresso 64mg", app: model)
        #expect(model.state.doses.first?.mg == 64 && model.state.doses.first?.source == "Espresso")
        try await expectInstantThenUndo()
    }

    @Test func instantTypedChipSizeSavesOnceWithUndo() async throws {
        assistant.savePolicySetting = .instant
        assistant.send("8oz coffee", app: model)
        #expect(model.state.doses.first?.mg == 95)
        try await expectInstantThenUndo()
    }

    @Test func instantStillConfirmsDefaultsDatabaseAndScaledAmounts() async throws {
        assistant.savePolicySetting = .instant
        for text in ["coffee", "12oz latte", "tea", "celsius", "matcha"] {
            assistant.send(text, app: model)
            #expect(assistant.pendingDraft != nil, "\(text)")
            #expect(model.state.doses.isEmpty, "\(text)")
        }
        await expectNothingWritten()
    }

    // Repeat-drink "Log It".

    private func repeatPrompt(mg: Double? = nil) async -> (Dose, ConversationMessage) {
        model.tick()
        let yesterday = model.addCustomDose(.init(mg: "95", source: "Drip", timestamp: model.now - dayMs, note: ""))
        await settleHealth()
        let prompt = RepeatDrinks.Prompt(doseID: yesterday.id, source: "Drip", mg: mg ?? 95, yesterdayAt: yesterday.timestamp, dueAt: model.now)
        var card = AssistantCard(kind: .repeatDrink, capturedAt: model.now, title: "Did you have a Drip?", summary: "")
        card.repeatDrink = prompt
        let message = ConversationMessage(text: card.title, intent: .logCaffeine, suggestionKey: prompt.id, card: card)
        assistant.conversation.messages.append(message)
        return (yesterday, message)
    }

    @Test func confirmRepeatDrinkWritesNothingBeforeSave() async throws {
        let (yesterday, message) = await repeatPrompt()
        assistant.reviewRepeatDrink(message, app: model)
        #expect(model.state.doses.map(\.id) == [yesterday.id] && assistant.pendingDraft?.mg == "95")
    }

    @Test func instantRepeatDrinkExactCopySavesOnceWithUndo() async throws {
        assistant.savePolicySetting = .instant
        let (yesterday, message) = await repeatPrompt()
        assistant.reviewRepeatDrink(message, app: model)
        #expect(model.state.doses.count == 2)
        let dose = try #require(model.state.doses.first { $0.id != yesterday.id })
        #expect(dose.mg == 95 && dose.source == "Drip")
        await settleHealth()
        #expect(health.savedSyncIdentifiers == [own(yesterday), own(dose)])
        let receipt = try #require(assistant.conversation.messages.last { $0.card?.kind == .receipt })
        assistant.undoReceipt(receipt, app: model)
        #expect(model.state.doses.map(\.id) == [yesterday.id])
        await settleHealth()
        #expect(health.deletedSyncIdentifiers == [own(dose)])
    }

    @Test func instantRepeatDrinkThatIsNotAnExactCopyConfirms() async throws {
        assistant.savePolicySetting = .instant
        let (yesterday, message) = await repeatPrompt(mg: 120)
        assistant.reviewRepeatDrink(message, app: model)
        #expect(model.state.doses.map(\.id) == [yesterday.id] && assistant.pendingDraft?.mg == "120")
    }

    // Shortcuts always confirm.

    @Test func instantStillConfirmsTheLogDrinkShortcut() async throws {
        assistant.savePolicySetting = .instant
        var request = CaffeineReviewShortcut(); request.request(drink: .espresso)
        assistant.reviewCaffeineShortcut(&request, app: model, foreground: true, coveringWork: false)
        #expect(assistant.pendingDraft?.mg == "60")
        await expectNothingWritten()
    }
}
