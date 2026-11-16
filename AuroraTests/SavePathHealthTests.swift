import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// v0.1.0 save rule, one test per path that can persist a drink. Each checks
/// (1) whether a dose is written, and only when the rule allows it,
/// (2) that Undo or delete removes exactly that entry and keeps an earlier one,
/// (3) that Aurora's own Health sample is written on save and deleted on Undo.
/// Instant with Undo: Quick Add chips. Everything else opens a card and
/// saves only on Save (typed, on-device proposal, photo, Review Drink,
/// Log Drink shortcut, repeat-drink "Log It"). Health is scripted.
@MainActor
@Suite struct SavePathHealthTests {
    let root: URL
    let health = ScriptedHealth()
    let model: AppModel
    let assistant: AssistantModel

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-save-paths-\(UUID().uuidString)", isDirectory: true)
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
    }

    /// An entry that must survive every Undo below.
    private func keptEntry() -> Dose {
        model.tick()
        return model.addCustomDose(.init(mg: "40", source: "Tea", timestamp: model.now - 3 * hourMs, note: "kept"))
    }

    private func settleHealth() async {
        await model.waitForHealthExports()
        await model.healthSync.runPendingActions()
    }

    private func own(_ dose: Dose) -> String { HealthOrigin.syncIdentifier(forDoseID: dose.id) }

    /// Save wrote exactly one new dose and its Health sample.
    private func expectSaved(besides kept: Dose) async throws -> Dose {
        #expect(model.state.doses.count == 2)
        let dose = try #require(model.state.doses.first { $0.id != kept.id })
        await settleHealth()
        #expect(health.savedSyncIdentifiers.contains(own(dose)))
        return dose
    }

    /// Undo removed exactly `dose`, kept `kept`, and deleted only its sample.
    private func expectUndone(_ dose: Dose, kept: Dose) async {
        #expect(model.state.doses.map(\.id) == [kept.id])
        await settleHealth()
        #expect(health.deletedSyncIdentifiers == [own(dose)])
    }

    private func undoLastReceipt() throws {
        let receipt = try #require(assistant.conversation.messages.last { $0.card?.kind == .receipt })
        #expect(receipt.card?.title == "Caffeine saved")
        assistant.undoReceipt(receipt, app: model)
    }

    // Instant with Undo (allowed): deterministic Quick Add chip.
    @Test func quickAddChipSavesAtOnceAndUndoRemovesOnlyItWithItsHealthSample() async throws {
        let kept = keptEntry()
        let dose = try #require(model.quickAdd(CaffeinePreset.all[0]))
        let saved = try await expectSaved(besides: kept)
        #expect(saved.id == dose.id)
        model.undo(dose)
        await expectUndone(dose, kept: kept)
    }

    // Manual typed entry: Log tab sheet Save (the sheet is the confirm).
    @Test func manualSheetSaveWritesAndUndoRemovesOnlyIt() async throws {
        let kept = keptEntry()
        model.tick()
        let dose = model.addCustomDose(.init(mg: "95", source: "Drip", timestamp: model.now - minuteMs, note: ""))
        _ = try await expectSaved(besides: kept)
        model.undo(dose)
        await expectUndone(dose, kept: kept)
    }

    // Typed request in the conversation: card first, Save writes.
    @Test func typedRequestOpensCardAndOnlySaveWrites() async throws {
        let kept = keptEntry()
        await assistant.handle(.logCaffeine, input: "I had 80 mg tea", app: model)
        #expect(model.state.doses.map(\.id) == [kept.id] && assistant.pendingDraft?.mg == "80")
        assistant.saveDose(app: model)
        let dose = try await expectSaved(besides: kept)
        try undoLastReceipt()
        await expectUndone(dose, kept: kept)
    }

    // Correction: "Actually tea" edits the open entry before Save; an edit of
    // a saved entry updates that same record and its own Health sample.
    @Test func correctionEditsTheSameEntryAndDeleteRemovesOnlyIt() async throws {
        let kept = keptEntry()
        await assistant.handle(.logCaffeine, input: "Log caffeine", app: model)
        assistant.pendingDraft?.mg = "80"; assistant.pendingDraft?.source = "Coffee"
        assistant.send("Actually tea", app: model)
        #expect(model.state.doses.map(\.id) == [kept.id] && assistant.pendingDraft?.source == "Tea")
        assistant.saveDose(app: model)
        let dose = try await expectSaved(besides: kept)
        #expect(dose.source == "Tea")
        var edit = CaffeineLog.editDraft(for: dose); edit.mg = "90"
        model.correctDose(id: dose.id, with: edit)
        #expect(model.state.doses.count == 2 && model.state.doses.first { $0.id == dose.id }?.mg == 90)
        await settleHealth()
        #expect(Set(health.savedSyncIdentifiers) == [own(kept), own(dose)])
        model.deleteDose(id: dose.id)
        await expectUndone(dose, kept: kept)
    }

    // On-device proposal: never saved without Save.
    @Test func onDeviceProposalWritesNothingUntilSave() async throws {
        let kept = keptEntry()
        assistant.extractLocalDrink = { _ in LocalDrinkUnderstanding.Evidence(route: "log", drink: "tea", amount: "80 mg", time: "now") }
        assistant.send("I had 80 mg tea now", app: model)
        await assistant.waitForCurrentRequest()
        #expect(model.state.doses.map(\.id) == [kept.id] && assistant.pendingDraft != nil)
        await settleHealth()
        #expect(health.savedSyncIdentifiers == [own(kept)])
        assistant.saveDose(app: model)
        let dose = try await expectSaved(besides: kept)
        try undoLastReceipt()
        await expectUndone(dose, kept: kept)
    }

    // Photo: the sheet's Save is the only write.
    @Test func photoSaveWritesOnlyOnSaveAndUndoRemovesOnlyIt() async throws {
        let kept = keptEntry()
        model.tick()
        let problem = assistant.savePhotoDose(.init(mg: "200", source: "Celsius", timestamp: model.now - minuteMs, note: ""), app: model)
        #expect(problem == nil)
        let dose = try await expectSaved(besides: kept)
        try undoLastReceipt()
        await expectUndone(dose, kept: kept)
    }

    // Review Drink shortcut: opens an empty card; nothing is written.
    @Test func reviewDrinkShortcutOpensCardAndOnlySaveWrites() async throws {
        let kept = keptEntry()
        await assistant.start(app: model)
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: model, foreground: true, coveringWork: false)
        #expect(model.state.doses.map(\.id) == [kept.id] && assistant.pendingDraft?.mg == "")
        assistant.pendingDraft?.mg = "80"; assistant.pendingDraft?.source = "Tea"
        assistant.saveDose(app: model)
        let dose = try await expectSaved(besides: kept)
        try undoLastReceipt()
        await expectUndone(dose, kept: kept)
    }

    // Log Drink shortcut: opens the card prefilled with the chosen drink; no
    // background save.
    @Test func logDrinkShortcutOpensPrefilledCardAndOnlySaveWrites() async throws {
        let kept = keptEntry()
        await assistant.start(app: model)
        var request = CaffeineReviewShortcut(); request.request(drink: .espresso)
        assistant.reviewCaffeineShortcut(&request, app: model, foreground: true, coveringWork: false)
        #expect(model.state.doses.map(\.id) == [kept.id])
        #expect(assistant.pendingDraft?.mg == "60" && assistant.pendingDraft?.source == "Espresso")
        assistant.saveDose(app: model)
        let dose = try await expectSaved(besides: kept)
        #expect(dose.mg == 60 && dose.source == "Espresso")
        try undoLastReceipt()
        await expectUndone(dose, kept: kept)
    }

    // Repeat-drink "Log It": opens the card with yesterday's drink.
    @Test func repeatDrinkLogItOpensCardAndOnlySaveWrites() async throws {
        let kept = keptEntry()
        await assistant.start(app: model)
        model.tick()
        let prompt = RepeatDrinks.Prompt(doseID: kept.id, source: "Drip", mg: 95, yesterdayAt: model.now - dayMs, dueAt: model.now)
        var card = AssistantCard(kind: .repeatDrink, capturedAt: model.now, title: "Did you have a Drip?", summary: "")
        card.repeatDrink = prompt
        let message = ConversationMessage(text: card.title, intent: .logCaffeine, suggestionKey: prompt.id, card: card)
        assistant.conversation.messages.append(message)
        assistant.reviewRepeatDrink(message, app: model)
        #expect(model.state.doses.map(\.id) == [kept.id])
        #expect(assistant.pendingDraft?.mg == "95" && assistant.pendingDraft?.source == "Drip")
        assistant.saveDose(app: model)
        let dose = try await expectSaved(besides: kept)
        try undoLastReceipt()
        await expectUndone(dose, kept: kept)
    }
}
