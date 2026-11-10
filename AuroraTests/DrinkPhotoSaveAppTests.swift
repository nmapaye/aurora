import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// Authored native fixtures for Log from Photo's Save (Nov 10 feedback, #88):
/// the standard saved-drink card with Undo for that exact entry. No camera,
/// Vision, model or system Health write is involved.
@MainActor
@Suite struct DrinkPhotoSaveAppTests {
    func app(_ root: URL) -> AppModel {
        let app = AppModel(makeStore: { StateStore(directory: root) }, legacy: { nil })
        app.load(); app.completeOnboarding()
        return app
    }
    func assistant() -> AssistantModel {
        AssistantModel(calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }
    func confirmedDraft(now: Millis) throws -> CustomDoseDraft {
        let db = try #require(CaffeineDatabase.bundled)
        let coffee = try #require(db.entries.first { $0.name == "Coffee, brewed" })
        var card = DrinkPhotoConfirmation(result: .candidates([.init(entry: coffee, score: 1, reason: .text)], confident: true),
                                          observation: .init(), timestamp: now - 60_000)
        card.choose(.listed(0))
        return try #require(card.draft(db: db, now: now))
    }

    @Test func photoSaveShowsTheSavedCardAndUndoRemovesThatEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        app.tick()
        let draft = try confirmedDraft(now: app.now)
        #expect(assistant.savePhotoDose(draft, app: app) == nil)
        #expect(app.state.doses.count == 1)
        let dose = try #require(app.state.doses.first)
        #expect(dose.note?.hasPrefix("Photo · ") == true)
        let receipt = try #require(assistant.conversation.messages.last)
        let card = try #require(receipt.card)
        #expect(card.kind == .receipt && card.state == .saved && card.title == "Caffeine saved")
        #expect(card.recordID == dose.id && card.recordKind == "caffeine")
        #expect(card.records.map(\.id) == [dose.id])
        let reopened = try #require(try StateStore(directory: root).load())
        #expect(reopened.doses == app.state.doses)
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
        #expect(assistant.conversation.messages.first { $0.id == receipt.id }?.card?.state == .undone)
    }

    @Test func refusedPhotoSaveWritesNothingAndShowsNoCard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        app.tick()
        var future = try confirmedDraft(now: app.now)
        future.timestamp = app.now + 3_600_000
        let count = assistant.conversation.messages.count
        #expect(assistant.savePhotoDose(future, app: app) != nil)
        #expect(app.state.doses.isEmpty && assistant.conversation.messages.count == count)
    }
}
