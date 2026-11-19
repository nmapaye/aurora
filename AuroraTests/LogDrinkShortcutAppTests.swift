import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// The Log Drink shortcut never saves in the background (v0.1.0 save rule):
/// it opens Aurora's review card prefilled with the chosen drink, and only
/// Save writes, with Undo for exactly that entry. No system Health writes
/// (Health choices stay off).
@MainActor
@Suite struct LogDrinkShortcutAppTests {
    func app(_ root: URL) -> AppModel {
        let app = AppModel(makeStore: { StateStore(directory: root) }, legacy: { nil })
        app.load(); app.completeOnboarding()
        return app
    }
    func assistant() -> AssistantModel {
        AssistantModel(calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }
    func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @Test func intentOpensTheAppAndOnlyHandsOverTheDrink() {
        #expect(LogDrinkIntent.openAppWhenRun)
    }

    @Test func chosenDrinkOpensPrefilledReviewAndNothingIsSavedUntilSave() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        var request = CaffeineReviewShortcut(); request.request(drink: .energy)
        // Not shown while Aurora is in the background: still waiting.
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: false, coveringWork: false)
        #expect(request.requested && assistant.pendingDraft == nil && app.state.doses.isEmpty)
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(!request.requested && app.state.doses.isEmpty)
        #expect(assistant.pendingDraft?.mg == "160" && assistant.pendingDraft?.source == "Energy")
        #expect(assistant.conversation.messages.last?.card?.kind == .caffeineDraft)
        assistant.saveDose(app: app)
        let dose = try #require(app.state.doses.first)
        #expect(app.state.doses.count == 1 && dose.mg == 160)
        let receipt = try #require(assistant.conversation.messages.last)
        #expect(receipt.card?.kind == .receipt && receipt.card?.recordID == dose.id)
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
    }

    @Test func usualPrefillsFromRecordsAndDiscardSavesNothing() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        app.tick()
        app.addCustomDose(.init(mg: "95", source: "Drip", timestamp: app.now - 2 * dayMs, note: ""))
        app.addCustomDose(.init(mg: "95", source: "Drip", timestamp: app.now - dayMs, note: ""))
        var request = CaffeineReviewShortcut(); request.request(drink: .usual)
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(assistant.pendingDraft?.mg == "95" && assistant.pendingDraft?.source == "Drip")
        assistant.discardDraft()
        #expect(app.state.doses.count == 2 && assistant.pendingDraft == nil)
    }
}
