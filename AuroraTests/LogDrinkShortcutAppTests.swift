import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// The Log Drink shortcut saves at once through the app model and its entry
/// can be undone from the shortcut, by voice, or from the conversation's
/// receipt. No system Health writes (Health choices stay off).
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

    @Test func presetSavesOnceDurablyAndARetryIsNotASecondDrink() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root)
        let outcome = try #require(app.logFromShortcut(.espresso))
        guard case .log(let dose) = outcome else { Issue.record("expected a new entry, got \(outcome)"); return }
        #expect(app.state.doses == [dose] && app.lastShortcutLog == dose)
        let reopened = try #require(try StateStore(directory: root).load())
        #expect(reopened.doses == [dose])
        // Siri re-running the intent after a slow reply saves nothing new.
        #expect(app.logFromShortcut(.espresso) == .alreadyLogged(dose))
        #expect(app.state.doses.count == 1)
    }

    @Test func usualWithNoHistorySavesNothing() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root)
        #expect(app.logFromShortcut(.usual) == .noUsualDrink)
        #expect(app.state.doses.isEmpty && app.lastShortcutLog == nil)
    }

    @Test func undoFromTheResultRemovesExactlyThatEntry() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root)
        guard case .log(let dose)? = app.logFromShortcut(.drip) else { Issue.record("not saved"); return }
        // A receipt for a different time (an entry corrected since) is left alone.
        #expect(app.undoShortcutLog(.init(doseID: dose.id, loggedAt: dose.timestamp - 1)) == nil)
        #expect(app.state.doses == [dose])
        #expect(app.undoShortcutLog(.init(dose)) == dose)
        #expect(app.state.doses.isEmpty && app.lastShortcutLog == nil)
        // A second Undo finds nothing.
        #expect(app.undoShortcutLog(.init(dose)) == nil)
        let reopened = try #require(try StateStore(directory: root).load())
        #expect(reopened.doses.isEmpty)
    }

    @Test func undoLastByVoiceWorksAfterTheConversationShowedTheReceipt() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        guard case .log(let dose)? = app.logFromShortcut(.matcha) else { Issue.record("not saved"); return }
        assistant.showShortcutLog(app: app)
        #expect(app.lastShortcutLog == dose)
        #expect(app.undoLastShortcutLog() == dose)
        #expect(app.state.doses.isEmpty)
    }

    @Test func conversationShowsOneReceiptWithUndoForTheShortcutEntry() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        guard case .log(let dose)? = app.logFromShortcut(.energy) else { Issue.record("not saved"); return }
        let before = assistant.conversation.messages.count
        assistant.showShortcutLog(app: app)
        assistant.showShortcutLog(app: app)
        #expect(assistant.conversation.messages.count == before + 1)
        let receipt = try #require(assistant.conversation.messages.last)
        #expect(receipt.card?.kind == .receipt && receipt.card?.recordID == dose.id && receipt.card?.title == "Caffeine saved")
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
        #expect(assistant.conversation.messages.first { $0.id == receipt.id }?.card?.state == .undone)
    }

    @Test func anEntryAlreadyUndoneGetsNoReceipt() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        guard case .log(let dose)? = app.logFromShortcut(.espresso) else { Issue.record("not saved"); return }
        // Undone from Siri's result before Aurora came to the foreground.
        _ = app.undoShortcutLog(.init(dose))
        let before = assistant.conversation.messages.count
        assistant.showShortcutLog(app: app)
        #expect(assistant.conversation.messages.count == before)
    }
}
