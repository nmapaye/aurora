import AuroraCore
import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct AssistantCardServiceTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func calendars() -> CalendarService { CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!) }
    private func app(_ directory: URL) -> AppModel {
        let app = AppModel(makeStore: { StateStore(directory: directory) }, legacy: { nil })
        app.load(); return app
    }
    @Test func migrationRetainsExactSourceAndVerifiesMessages() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var legacy = ConversationState(); legacy.version = 1
        legacy.messages = [.init(text: "Old answer", intent: .weeklyTrends)]
        try store.save(legacy)
        let original = try Data(contentsOf: store.url)
        let loaded = try store.load()
        #expect(loaded.version == 2 && loaded.messages == legacy.messages)
        #expect(loaded.messages.first?.card == nil)
        #expect(try Data(contentsOf: directory.appendingPathComponent("conversation.v1-source.json")) == original)
        #expect(try store.load() == loaded)
    }
    @Test func futureConversationVersionIsPreserved() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var state = ConversationState(); state.version = 99
        try store.save(state)
        let original = try Data(contentsOf: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == original)
    }
    @Test func relaunchExpiresDraftsAndCalendarWithoutChangingSnapshots() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var state = ConversationState()
        let kinds: [AssistantCard.Kind] = [.caffeineDraft, .sleepDraft, .calendar, .energy]
        state.messages = kinds.map { .init(text: "Snapshot", card: .init(kind: $0, capturedAt: 123, title: "Snapshot")) }
        try store.save(state)
        let app = app(directory.appendingPathComponent("records"))
        let assistant = AssistantModel(calendars: calendars(), makeStore: { store })
        await assistant.start(app: app)
        #expect(assistant.conversation.messages.compactMap(\.card).prefix(3).allSatisfy { $0.state == .expired })
        #expect(assistant.conversation.messages.last?.card?.state == .ready)
        #expect(assistant.conversation.messages.allSatisfy { $0.card?.capturedAt == 123 })
        #expect(assistant.activeCards.isEmpty && assistant.pendingDraft == nil && assistant.pendingSleep == nil)
    }
    /// Typing in an open draft changes only the draft; its card is written
    /// when the app goes inactive and when the draft closes.
    @Test func draftEditsReachTheCardOnlyWhenCapturedOrClosed() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logCaffeine, input: "Log caffeine", app: app)
        let id = try #require(assistant.pendingMessageID)
        let opened = assistant.conversation
        assistant.pendingDraft?.mg = "123"
        assistant.pendingDraft?.source = "Tea"
        #expect(assistant.conversation == opened)
        func card() -> AssistantCard? { assistant.conversation.messages.first { $0.id == id }?.card }
        func value(_ metric: String) -> String? { card()?.metrics.first { $0.id == metric }?.value }
        // Going inactive: the open card keeps the last values for a relaunch.
        assistant.captureDraft(app: app)
        #expect(card()?.state == .ready && value("amount") == "123 mg" && value("source") == "Tea")
        assistant.pendingDraft?.mg = "150"
        assistant.discardDraft()
        #expect(card()?.state == .discarded && value("amount") == "150 mg")
        // A saved check-in's card shows the rating chosen, not the opening one.
        await assistant.handle(.energyCheckIn, input: "Check in my energy", app: app)
        let checkIn = try #require(assistant.pendingMessageID)
        assistant.pendingCheckIn?.rating = 4
        assistant.saveCheckIn(app: app)
        let saved = try #require(assistant.conversation.messages.first { $0.id == checkIn }?.card)
        #expect(saved.state == .saved && saved.metrics.first { $0.id == "rating" }?.missing == false)
    }
    @Test func cardFocusIsReleasedOnlyByItsOwnCard() {
        let assistant = AssistantModel(calendars: calendars())
        let a = UUID(), b = UUID()
        assistant.cardFocus(a, focused: true)
        assistant.cardFocus(b, focused: true)
        // A's late release must not clear B, which now holds focus.
        assistant.cardFocus(a, focused: false)
        #expect(assistant.editingCardField && assistant.focusedCards == [b])
        assistant.cardFocus(b, focused: false)
        #expect(!assistant.editingCardField && assistant.focusedCards.isEmpty)
        assistant.cardFocus(a, focused: true)
        assistant.resetAfterErase()
        #expect(!assistant.editingCardField && assistant.focusedCards.isEmpty)
        assistant.cardFocus(b, focused: true)
        assistant.clearCardFocus()
        #expect(assistant.focusedCards.isEmpty)
        // Focus tracking is interaction state, never part of the conversation.
        #expect(assistant.conversation == ConversationState())
    }
    @Test func repeatedSaveAndUndoCannotDuplicateOrRemoveAnotherRecord() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logCaffeine, input: "I had 80 mg tea", app: app)
        assistant.saveDose(app: app); assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1)
        let receipt = try #require(assistant.conversation.messages.last)
        assistant.undoReceipt(receipt, app: app); assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
        #expect(assistant.conversation.messages.last?.card?.state == .undone)
    }
    @Test func sourceCorrectionRequiresSaveAndKeepsOtherDraftFields() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logCaffeine, input: "I had 80 mg coffee", app: app)
        let previous = try #require(assistant.pendingDraft)
        assistant.send("Actually tea", app: app)
        #expect(assistant.pendingDraft?.source == "Tea")
        #expect(assistant.pendingDraft?.mg == previous.mg && assistant.pendingDraft?.timestamp == previous.timestamp)
        #expect(app.state.doses.isEmpty && !assistant.processing)
        assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1 && app.state.doses.first?.source == "Tea")
    }
    @Test func changedRecordCannotBeUndoneFromAnOldReceipt() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logCaffeine, input: "I had 80 mg tea", app: app)
        assistant.saveDose(app: app)
        let receipt = try #require(assistant.conversation.messages.last)
        let dose = try #require(app.state.doses.first)
        var draft = CaffeineLog.editDraft(for: dose); draft.note = "Corrected"
        app.correctDose(id: dose.id, with: draft)
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.count == 1 && assistant.failure != nil)
    }
    @Test func failedRecordSaveKeepsDraftAndProducesNoReceipt() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logCaffeine, input: "I had 80 mg tea", app: app)
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        assistant.saveDose(app: app)
        #expect(app.state.doses.isEmpty && assistant.pendingDraft != nil)
        #expect(assistant.conversation.messages.last?.card?.kind == .caffeineDraft)
        #expect(assistant.failure != nil)
    }
    @Test func clearingConversationAlsoRemovesRetainedMigrationSource() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var legacy = ConversationState(); legacy.version = 1; legacy.preferences.proactive = false
        legacy.messages = [.init(text: "Legacy conversation")]
        try store.save(legacy)
        let app = app(directory.appendingPathComponent("records"))
        let assistant = AssistantModel(calendars: calendars(), makeStore: { store })
        await assistant.start(app: app)
        assistant.clearConversation()
        #expect(try store.load().messages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("conversation.v1-source.json").path))
        #expect(app.phase == .ready)
    }
    @Test func clearedConversationOpensOnItsWelcome() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        let app = app(directory.appendingPathComponent("records"))
        let assistant = AssistantModel(calendars: calendars(), makeStore: { store })
        await assistant.start(app: app)
        await assistant.handle(.logCaffeine, input: "I had 80 mg tea", app: app)
        #expect(assistant.clearConversation(app: app))
        #expect(assistant.conversation.messages.map(\.card?.kind) == [.welcome])
        #expect(try store.load().messages.map(\.card?.kind) == [.welcome])
        #expect(assistant.pendingDraft == nil && assistant.failure == nil)
    }
    @Test func briefingRefreshReadsCalendarsAndKeepsPriorSnapshot() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let fixture = CalendarFixture(.apple)
        fixture.event.start = Date(timeIntervalSince1970: app.now / 1000)
        fixture.event.end = fixture.event.start.addingTimeInterval(600)
        let service = CalendarService(providers: [fixture], defaults: UserDefaults(suiteName: UUID().uuidString)!)
        service.selected = ["apple:c"]
        let assistant = AssistantModel(calendars: service)
        await assistant.handle(.briefing, input: "Morning briefing", app: app)
        let original = try #require(assistant.conversation.messages.last?.card)
        fixture.event.title = "Updated commitment"
        await assistant.handle(.briefing, input: "Morning briefing", app: app)
        #expect(original.commitments.first?.title == "Study")
        #expect(assistant.conversation.messages.last?.card?.commitments.first?.title == "Updated commitment")
        #expect(fixture.reads == 2 && fixture.writes == 0)
    }
    /// A new conversation opens on the short welcome; the full capabilities
    /// card waits for "What can you do?".
    @Test func aNewConversationOpensOnTheWelcome() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        let app = app(directory.appendingPathComponent("records"))
        let assistant = AssistantModel(calendars: calendars(), makeStore: { store })
        await assistant.start(app: app)
        #expect(assistant.conversation.messages.first?.card?.kind == .welcome)
        #expect(assistant.conversation.messages.first?.card?.title == "Ready when you are.")
        #expect(!assistant.conversation.messages.contains { $0.card?.kind == .capabilities })
        #expect(try store.load().messages.first?.card?.kind == .welcome)
    }
    @Test func interruptedReadBecomesRefreshableFailureAfterRelaunch() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        var state = ConversationState()
        var card = AssistantCard(kind: .briefing, capturedAt: 123, title: "Your recorded day")
        card.state = .loading; state.messages = [.init(text: "Loading", card: card)]
        try store.save(state)
        let app = app(directory.appendingPathComponent("records"))
        let assistant = AssistantModel(calendars: calendars(), makeStore: { store })
        await assistant.start(app: app)
        #expect(assistant.conversation.messages.first?.card?.state == .failed)
        #expect(assistant.conversation.messages.first?.card?.refreshIntent == .briefing)
    }
    /// With no usual night on record, nothing is proposed: both times start
    /// empty, the card says so, and Save records nothing until both are set.
    @Test func sleepReviewStartsEmptyAndSavesOnlyTheTimesAdded() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logSleep, input: "Log sleep", app: app)
        #expect(assistant.pendingSleep == ManualSleep.Entry())
        let id = try #require(assistant.pendingMessageID)
        let card = try #require(assistant.conversation.messages.first { $0.id == id }?.card)
        #expect(card.metrics.filter(\.missing).map(\.id) == ["start", "end"])
        assistant.saveSleep(app: app)
        #expect(app.state.sleeps.isEmpty)
        #expect(assistant.failure == ManualSleep.missingTimes)
        // Read before writing: reading pendingSleep inside its own
        // assignment is a simultaneous access, which crashes the test host.
        let end = ManualSleep.addedTime(now: app.now)
        assistant.pendingSleep?.end = end
        assistant.pendingSleep?.start = end - 7 * hourMs
        assistant.saveSleep(app: app)
        #expect(app.state.sleeps.count == 1)
        #expect(app.state.sleeps.first.map { $0.end - $0.start } == 7 * hourMs)
    }
    @Test func reminderTimesUseTheLocaleClock() {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        assistant.conversation.preferences.proactive = true
        assistant.conversation.preferences.morningBriefing = true
        assistant.conversation.preferences.briefingHour = 8
        let metrics = assistant.reminderMetrics(app: app)
        let hour = { (value: Int) in app.text.clockHour(Double(value), clock: app.clock) }
        #expect(metrics.first { $0.id == "briefing" }?.value == hour(8))
        let p = assistant.conversation.preferences
        #expect(metrics.first { $0.id == "quiet" }?.value == "\(hour(p.quietStartHour))–\(hour(p.quietEndHour))")
    }
    @Test func invalidSleepProducesNoSuccessReceipt() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let app = app(directory)
        let assistant = AssistantModel(calendars: calendars())
        await assistant.handle(.logSleep, input: "Log sleep", app: app)
        assistant.pendingSleep = .init(start: app.now, end: app.now - hourMs, note: "")
        assistant.saveSleep(app: app)
        #expect(app.state.sleeps.isEmpty)
        #expect(assistant.conversation.messages.last?.card?.kind == .sleepDraft)
        #expect(assistant.failure != nil)
    }
}

@MainActor
private final class CalendarFixture: CommitmentProvider {
    let providerID: CalendarProviderID
    var event: Commitment
    var failWrite = false
    var revoked = false
    var writes = 0
    var reads = 0
    init(_ id: CalendarProviderID) {
        providerID = id
        event = .init(id: "e", calendarID: "c", provider: id, title: "Study", start: .now.addingTimeInterval(3600), end: .now.addingTimeInterval(7200), timeZone: "America/Los_Angeles", revision: "v1", canMove: true, recurring: true)
    }
    func calendars() async throws -> [AssistantCalendar] { revoked ? [] : [.init(id: "c", provider: providerID, title: "Personal", writable: true)] }
    func events(calendarIDs: [String], from: Date, to: Date) async throws -> [Commitment] { reads += 1; return [event] }
    func current(_ event: Commitment) async throws -> Commitment { self.event }
    func move(_ change: CalendarChange) async throws -> Commitment {
        if failWrite { throw CalendarActionError.unavailable }
        writes += 1; event.start = change.newStart; event.end = change.newEnd; event.revision = "v2"; return event
    }
}

@MainActor
@Suite struct CalendarFixtureTests {
    @Test(arguments: [CalendarProviderID.apple, .google]) func approveOnceAndRejectStale(provider: CalendarProviderID) async throws {
        let fixture = CalendarFixture(provider)
        let service = CalendarService(providers: [fixture], defaults: UserDefaults(suiteName: UUID().uuidString)!)
        service.selected = ["\(provider.rawValue):c"]
        await service.refreshCalendars()
        let change = CalendarChange(original: fixture.event, newStart: fixture.event.start.addingTimeInterval(3600), newEnd: fixture.event.end.addingTimeInterval(3600))
        _ = try await service.approve(change)
        #expect(fixture.writes == 1)
        do { _ = try await service.approve(change); Issue.record("Duplicate approval accepted") } catch { #expect(error as? CalendarActionError == .approvalRequired) }
        do { _ = try await service.approve(.init(original: change.original, newStart: change.newStart, newEnd: change.newEnd)); Issue.record("Stale approval accepted") } catch { #expect(error as? CalendarActionError == .stale) }
        #expect(fixture.writes == 1)
    }
    @Test func revokedSelectionBlocksAndFailedWriteDoesNotClaimSuccess() async throws {
        let fixture = CalendarFixture(.apple)
        let service = CalendarService(providers: [fixture], defaults: UserDefaults(suiteName: UUID().uuidString)!)
        service.selected = ["apple:c"]
        fixture.revoked = true; await service.refreshCalendars(); await service.refresh()
        #expect(service.message != nil)
        let change = CalendarChange(original: fixture.event, newStart: fixture.event.start.addingTimeInterval(3600), newEnd: fixture.event.end.addingTimeInterval(3600))
        do { _ = try await service.approve(change); Issue.record("Revoked calendar written") } catch { #expect(error as? CalendarActionError == .unavailable) }
        fixture.revoked = false; fixture.failWrite = true; await service.refreshCalendars()
        do { _ = try await service.approve(.init(original: fixture.event, newStart: change.newStart, newEnd: change.newEnd)); Issue.record("Failed write reported success") } catch { #expect(error as? CalendarActionError == .unavailable) }
        #expect(fixture.writes == 0)
    }
}
