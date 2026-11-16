import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// AI-off typed drink entry in the conversation (CPO, Nov 16): a simple
/// typed drink opens a filled entry card and writes nothing; an unreadable
/// one gets a plain message and the manual card.
@MainActor
@Suite struct TypedDrinkEntryAppTests {
    func make() async -> (AppModel, AssistantModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = AppModel(makeStore: { StateStore(directory: root) }, legacy: { nil })
        app.load(); app.completeOnboarding()
        let assistant = AssistantModel(calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!),
                                       makeStore: { ConversationStore(directory: root) })
        await assistant.start(app: app)
        assistant.intelligenceOffOverride = true
        return (app, assistant, root)
    }

    @Test func typedDrinkOpensAFilledCardThatNamesItsSourceAndWritesNothing() async throws {
        let (app, assistant, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        assistant.send("12oz coffee", app: app)
        #expect(app.state.doses.isEmpty)
        let draft = try #require(assistant.pendingDraft)
        #expect(draft.mg == "142" && draft.source == "Coffee")
        #expect(assistant.draftSourceLine.hasPrefix("USDA · FDC 171890 · scaled to 12 fl oz"))
        #expect(assistant.conversation.messages.last?.card?.kind == .caffeineDraft)
        // Editing the amount makes it the person's own number.
        assistant.pendingDraft?.mg = "150"
        #expect(assistant.draftSourceLine == TypedDrinkEntry.manualSourceLine)
        assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1 && app.state.doses.first?.mg == 150)
    }

    @Test func bareCoffeeShowsTheQuickAddDefault() async throws {
        let (app, assistant, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        assistant.send("coffee", app: app)
        #expect(app.state.doses.isEmpty && assistant.pendingDraft?.mg == "95")
        #expect(assistant.draftSourceLine == "Quick Add Default · 8 fl oz · local time")
    }

    @Test func unreadableDrinkGetsAPlainMessageAndTheManualCard() async throws {
        let (app, assistant, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        assistant.send("coffee and tea", app: app)
        #expect(app.state.doses.isEmpty)
        #expect(assistant.conversation.messages.contains { $0.text == TypedDrinkEntry.oneDrinkMessage })
        #expect(assistant.pendingDraft?.mg == "" && assistant.conversation.messages.last?.card?.kind == .caffeineDraft)
    }

    @Test func questionsAreNotDrinkEntries() async throws {
        let (app, assistant, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        assistant.send("how much coffee should I drink", app: app)
        await assistant.waitForCurrentRequest()
        #expect(app.state.doses.isEmpty && assistant.pendingDraft == nil)
    }
}
