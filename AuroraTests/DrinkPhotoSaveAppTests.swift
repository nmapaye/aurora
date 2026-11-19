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

    // Sheet level (CPO review of ef7fb1ce): drive the sheet's own review and
    // Save steps (DrinkPhotoSheetFlow, which DrinkPhotoSheet calls from
    // begin, its Save button and Cancel) instead of calling savePhotoDose.
    func barcodeObservation(_ db: CaffeineDatabase) throws -> DrinkPhotoObservation {
        let entry = try #require(db.entries.first { $0.gtin != nil && !$0.servings.isEmpty })
        return DrinkPhotoObservation(barcodes: [try #require(entry.gtin)])
    }

    @Test func photoSheetReviewWritesNothingAndOnlySaveWritesOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        app.tick()
        let db = try #require(CaffeineDatabase.bundled)
        let messages = assistant.conversation.messages.count
        var flow = DrinkPhotoSheetFlow()
        // The read finishes: a confident barcode match fills the card.
        flow.review(try barcodeObservation(db), db: db, now: app.now - 60_000)
        flow.edit { $0.choose(.listed(0)) }
        #expect(flow.isReviewing && !flow.saved)
        let draft = try #require(flow.draft(db: db, now: app.now))
        // A complete card is still only a card: no dose, no Health export, no receipt.
        #expect(app.state.doses.isEmpty && assistant.conversation.messages.count == messages)
        flow.edit { $0.type(mg: "80") }
        flow.edit { $0.clearTypedAmount() }
        #expect(app.state.doses.isEmpty)
        // Save is the only write, and a second tap adds nothing.
        #expect(flow.save(db: db, assistant: assistant, app: app) == .saved)
        #expect(app.state.doses.count == 1)
        let dose = try #require(app.state.doses.first)
        #expect(dose.mg == Double(draft.mg) && dose.note?.hasPrefix("Photo · ") == true)
        #expect(flow.save(db: db, assistant: assistant, app: app) == .alreadySaved)
        #expect(app.state.doses.count == 1)
        let receipt = try #require(assistant.conversation.messages.last { $0.card?.kind == .receipt })
        #expect(receipt.card?.recordID == dose.id)
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
    }

    @Test func photoSheetCancelWritesNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        app.tick()
        let db = try #require(CaffeineDatabase.bundled)
        let messages = assistant.conversation.messages.count
        var flow = DrinkPhotoSheetFlow()
        flow.review(try barcodeObservation(db), db: db, now: app.now - 60_000)
        flow.edit { $0.choose(.listed(0)) }
        flow.close()
        #expect(!flow.isReviewing && flow.draft(db: db, now: app.now) == nil)
        // Save after Cancel has no card to save.
        guard case .problem = flow.save(db: db, assistant: assistant, app: app) else { Issue.record("saved after Cancel"); return }
        #expect(app.state.doses.isEmpty && assistant.conversation.messages.count == messages)
        let reopened = try StateStore(directory: root).load()
        #expect(reopened?.doses.isEmpty ?? true)
    }
}
