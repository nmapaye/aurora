import AuroraCore
import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct EnergyCheckInAppTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func calendars() -> CalendarService { CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!) }
    private func app(_ directory: URL) -> AppModel {
        let app = AppModel(makeStore: { StateStore(directory: directory) }, legacy: { nil })
        app.load(); return app
    }

    @Test func saveNeedsARatingAndRepeatedTapsAddOneRecord() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.energyCheckIn, input: "Check in my energy", app: app)
        #expect(assistant.pendingCheckIn?.rating == nil)
        assistant.saveCheckIn(app: app)
        #expect(app.state.energyCheckIns.isEmpty && assistant.failure == "Choose a rating from 1 to 5.")
        assistant.pendingCheckIn?.rating = 4
        assistant.saveCheckIn(app: app); assistant.saveCheckIn(app: app)
        #expect(app.state.energyCheckIns.count == 1 && app.state.energyCheckIns.first?.rating == 4)
        #expect(assistant.pendingCheckIn == nil)
        let receipt = try #require(assistant.conversation.messages.last?.card)
        #expect(receipt.recordKind == "checkin" && receipt.checkIn?.saved == app.state.energyCheckIns.first)
    }

    @Test func statedRatingAndCorrectionsFillTheReviewOnly() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.energyCheckIn, input: "I feel 2 out of 5", app: app)
        #expect(assistant.pendingCheckIn?.rating == 2)
        assistant.send("actually 4", app: app)
        #expect(assistant.pendingCheckIn?.rating == 4 && !assistant.processing)
        assistant.send("make it 9", app: app)
        #expect(assistant.pendingCheckIn?.rating == 4)
        #expect(app.state.energyCheckIns.isEmpty)
        // If a classifier ever routes an unrelated rating here, nothing is prefilled.
        await assistant.handle(.energyCheckIn, input: "I rated that movie 4/5", app: app)
        #expect(assistant.pendingCheckIn?.rating == nil && app.state.energyCheckIns.isEmpty)
    }

    @Test func failedWriteKeepsTheReviewOpenForRetry() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.energyCheckIn, input: "Check in my energy", app: app)
        assistant.pendingCheckIn?.rating = 3
        let file = directory.appendingPathComponent("state.json")
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        assistant.saveCheckIn(app: app)
        #expect(app.state.energyCheckIns.isEmpty && assistant.failure != nil)
        #expect(assistant.pendingCheckIn?.rating == 3)
        try FileManager.default.removeItem(at: file)
        assistant.saveCheckIn(app: app)
        #expect(app.state.energyCheckIns.count == 1 && assistant.pendingCheckIn == nil)
    }

    @Test func undoAndCorrectionRevalidateTheExactRecord() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.energyCheckIn, input: "Check in my energy", app: app)
        assistant.pendingCheckIn?.rating = 2
        assistant.saveCheckIn(app: app)
        let first = try #require(assistant.conversation.messages.last)
        assistant.editCheckIn(first, app: app)
        assistant.pendingCheckIn?.rating = 5
        assistant.saveCheckIn(app: app)
        #expect(app.state.energyCheckIns.map(\.rating) == [5])
        // The first receipt is stale now; it must not remove the corrected record.
        assistant.undoCheckIn(first, app: app)
        #expect(app.state.energyCheckIns.map(\.rating) == [5] && assistant.failure != nil)
        let correction = try #require(assistant.conversation.messages.last)
        assistant.undoCheckIn(correction, app: app)
        #expect(app.state.energyCheckIns.map(\.rating) == [2])
        #expect(assistant.conversation.messages.last?.card?.state == .undone)
        assistant.undoCheckIn(first, app: app)
        #expect(app.state.energyCheckIns.isEmpty)
    }

    @Test func eraseAndDeleteAllClearCheckInsAndOpenReviews() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.energyCheckIn, input: "Check in my energy", app: app)
        assistant.pendingCheckIn?.rating = 3
        assistant.saveCheckIn(app: app)
        await assistant.handle(.energyCheckIn, input: "Check in my energy", app: app)
        app.deleteAllData()
        #expect(app.state.energyCheckIns.isEmpty)
        assistant.resetAfterErase()
        #expect(assistant.pendingCheckIn == nil && assistant.conversation.messages.isEmpty)
    }

    @Test func relaunchExpiresAnOpenCheckInAndKeepsEnergySnapshots() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        let records = app(directory.appendingPathComponent("records"))
        let projection = AssistantCards.make(.energyProjection, state: records.state, now: records.now, clock: records.clock, text: records.text)
        var state = ConversationState()
        state.messages = [
            .init(text: "Check-in", card: .init(kind: .energyCheckIn, capturedAt: 123, title: "Energy check-in")),
            .init(text: "Curve", card: projection),
        ]
        try store.save(state)
        let assistant = AssistantModel(calendars: calendars(), makeStore: { store })
        await assistant.start(app: records)
        #expect(assistant.conversation.messages.first?.card?.state == .expired)
        #expect(assistant.conversation.messages[1].card == projection)
        #expect(assistant.pendingCheckIn == nil)
    }
}
