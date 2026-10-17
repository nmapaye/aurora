import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// Scroll decisions for added messages, the shared column inset, the
/// gallery's Health rows and fixture isolation. No timing or sleeps.
@MainActor
@Suite struct ConversationPolishTests {
    private func messages(_ count: Int, userAt: Set<Int> = []) -> [ConversationMessage] {
        (0..<count).map { ConversationMessage(text: "Message \($0)", isUser: userAt.contains($0)) }
    }

    @Test func aNewReplyShowsItsStartWhenTheLatestWasOnScreen() {
        let list = messages(4)
        #expect(ConversationReveal.after(list, previousCount: 3, readingLatest: true) == .start(list[3].id))
    }

    @Test func readingEarlierMessagesKeepsThePlaceAndHoldsTheFirstNewReply() {
        let list = messages(5)
        #expect(ConversationReveal.after(list, previousCount: 3, readingLatest: false) == .hold(list[3].id))
    }

    @Test func thePersonsOwnMessageAndTheOpenedConversationShowTheEnd() {
        let sent = messages(4, userAt: [3])
        #expect(ConversationReveal.after(sent, previousCount: 3, readingLatest: false) == .end)
        #expect(ConversationReveal.after(messages(6), previousCount: 0, readingLatest: false) == .end)
    }

    /// A new conversation is read from its welcome's top; one with the
    /// person's messages opens at the end as before.
    @Test func aNewConversationOpensAtItsWelcomeFromTheTop() {
        let welcome = ConversationMessage(text: "Ready when you are.", card: .init(kind: .welcome, capturedAt: 0, title: "Ready when you are."))
        #expect(ConversationReveal.after([welcome], previousCount: 0, readingLatest: false) == .top)
        #expect(ConversationReveal.after([welcome] + messages(2), previousCount: 0, readingLatest: false) == .top)
        #expect(ConversationReveal.after([welcome] + messages(2, userAt: [1]), previousCount: 0, readingLatest: false) == .end)
    }

    /// A tile's request can be answered in the same update as the person's
    /// message; the reply is shown from its start, never scrolled past it.
    @Test func theOwnMessageAndItsReplyTogetherShowTheReplysStart() {
        let list = messages(5, userAt: [3])
        #expect(ConversationReveal.after(list, previousCount: 3, readingLatest: false) == .start(list[4].id))
    }

    @Test func removalsAndClearsMoveNothing() {
        let list = messages(2)
        #expect(ConversationReveal.after(list, previousCount: 2, readingLatest: true) == .none)
        #expect(ConversationReveal.after(list, previousCount: 5, readingLatest: false) == .none)
        #expect(ConversationReveal.after([], previousCount: 3, readingLatest: true) == .none)
    }

    @Test func theWindowShowsTheLatestAndKeepsItsTopAsMessagesArrive() {
        #expect(ConversationWindow.first(nil, count: 0) == 0)
        #expect(ConversationWindow.first(nil, count: 12) == 0)
        #expect(ConversationWindow.first(nil, count: 100) == 60)
        // A reply joins below; the top message stays the same.
        let start = ConversationWindow.start(nil, count: 101, previousCount: 100)
        #expect(start == 60)
        #expect(ConversationWindow.first(start, count: 101) == 60)
        #expect(ConversationWindow.start(25, count: 103, previousCount: 101) == 25)
    }

    @Test func showingEarlierAddsABatchUntilTheFirstMessage() {
        let once = ConversationWindow.earlier(nil, count: 100)
        #expect(once == 40)
        let twice = ConversationWindow.earlier(once, count: 100)
        #expect(twice == 20)
        #expect(ConversationWindow.earlier(ConversationWindow.earlier(twice, count: 100), count: 100) == 0)
    }

    @Test func openingClearingOrRemovingKeepsTheLatestShown() {
        // Opening the stored conversation, and clearing it, show the latest.
        #expect(ConversationWindow.start(10, count: 100, previousCount: 0) == nil)
        #expect(ConversationWindow.start(10, count: 0, previousCount: 100) == nil)
        // A removal keeps the revealed batches; the latest are always shown.
        #expect(ConversationWindow.start(10, count: 99, previousCount: 100) == 10)
        #expect(ConversationWindow.first(70, count: 50) == 10)
        #expect(ConversationWindow.first(70, count: 1) == 0)
    }

    @Test func theWindowNeverRendersMoreThanTheCapAndKeepsTheLatest() {
        let count = 400
        var start: Int?
        for _ in 0..<30 {
            start = ConversationWindow.earlier(start, count: count)
            let shown = ConversationWindow.shown(start, count: count)
            #expect(shown.reduce(0) { $0 + $1.count } <= ConversationWindow.cap)
            #expect(shown.last?.upperBound == count)
            #expect(shown.last.map { $0.count >= ConversationWindow.latest } == true)
        }
        // Showing earlier reaches the first message; the batch beside the
        // latest is the one left out.
        #expect(ConversationWindow.shown(start, count: count) == [0..<80, 360..<400])
        // Up to the cap the window is one run of messages.
        #expect(ConversationWindow.shown(nil, count: 100) == [60..<100])
        #expect(ConversationWindow.shown(280, count: 400) == [280..<400])
        #expect(ConversationWindow.shown(260, count: 400) == [260..<340, 360..<400])
    }

    @Test func showingLaterClosesTheGapABatchAtATime() {
        #expect(ConversationWindow.later(0, count: 400) == 20)
        #expect(ConversationWindow.shown(20, count: 400) == [20..<100, 360..<400])
        // The last step joins the two parts at exactly the cap.
        #expect(ConversationWindow.later(270, count: 400) == 280)
        #expect(ConversationWindow.shown(280, count: 400) == [280..<400])
        // Without a gap nothing moves.
        #expect(ConversationWindow.later(nil, count: 100) == 60)
        #expect(ConversationWindow.later(280, count: 400) == 280)
    }

    @Test func rowsGroupByTimeAndMarkTheGap() {
        var list = messages(200)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in list.indices { list[index].createdAt = base.addingTimeInterval(Double(index) * 60) }
        list[170].createdAt = list[169].createdAt.addingTimeInterval(ConversationRow.groupGap + 1)
        for index in 171..<200 { list[index].createdAt = list[170].createdAt.addingTimeInterval(Double(index - 170) * 60) }
        let rows = ConversationWindow.rows(list, start: 0)
        #expect(rows.map(\.id) == (Array(list[0..<80]) + Array(list[160..<200])).map(\.id))
        #expect(rows.filter(\.startsGroup).map(\.message.text) == ["Message 0", "Message 160", "Message 170"])
        #expect(rows.filter(\.afterGap).map(\.message.text) == ["Message 160"])
        #expect(ConversationWindow.rows(list, start: nil).allSatisfy { !$0.afterGap })
        #expect(ConversationWindow.rows([], start: nil).isEmpty)
    }

    @Test func userMessageCountStopsAtWhatItNeeds() {
        #expect(!messages(5).hasUserMessages(atLeast: 1))
        #expect(messages(5, userAt: [4]).hasUserMessages(atLeast: 1))
        #expect(!messages(5, userAt: [1, 3]).hasUserMessages(atLeast: 3))
        #expect(messages(9, userAt: [1, 3, 8]).hasUserMessages(atLeast: 3))
        #expect([ConversationMessage]().hasUserMessages(atLeast: 0))
    }

    @Test func theLongConversationFixtureNeedsItsArgument() {
        #expect(AssistantModel.uiTestConversation([]).messages.isEmpty)
        let long = AssistantModel.uiTestConversation(["-AuroraUITestLongConversation"]).messages
        #expect(long.count > ConversationWindow.latest + ConversationWindow.batch)
    }

    /// The same column as the message list: `contentMaxWidth`, centered,
    /// at least `lg` from each edge.
    @Test func columnInsetMatchesTheConversationColumn() {
        #expect(Metrics.columnInset(containerWidth: 0) == Metrics.lg)
        #expect(Metrics.columnInset(containerWidth: 390) == Metrics.lg)
        let pad: CGFloat = 1032
        let inset = Metrics.columnInset(containerWidth: pad)
        #expect(pad - 2 * inset == Metrics.contentMaxWidth)
        #expect(Metrics.columnInset(containerWidth: Metrics.contentMaxWidth + 2 * Metrics.lg) == Metrics.lg)
    }

    @Test func receiptHealthRowsUseTheAppsStatusCopy() {
        #expect(AssistantModel.healthMetric(.notExported) == nil)
        let pending = AssistantModel.healthMetric(.pending(.saveCaffeine))
        #expect(pending?.value == HealthExportStatus.pending(.saveCaffeine).value)
        #expect(pending?.detail == HealthExportStatus.pending(.saveCaffeine).detail)
        #expect(AssistantModel.healthMetric(.failed(.saveCaffeine, nil))?.missing == HealthExportStatus.failed(.saveCaffeine, nil).needsAttention)
        for fixture in DesignGalleryView.ReceiptHealth.allCases {
            if let status = fixture.status { #expect(AssistantModel.healthMetric(status) != nil) }
        }
    }

    /// Fixture saves fail on demand and succeed again for a retry, inside the
    /// fixture's own folder; calendar selection never reaches app defaults.
    @Test func setupFixtureSaveFailureThenRetry() throws {
        let fixture = GalleryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.app.load()
        #expect(fixture.app.recordSetup(.name, .answered) { $0.prefs.displayName = "Synthetic" })
        fixture.failSaves(true)
        #expect(!fixture.app.recordSetup(.sleepTarget, .skipped))
        #expect(fixture.app.mutationFailure != nil)
        #expect(SetupStep(stored: fixture.app.state.onboarding.setupStep) == .sleepTarget)
        fixture.failSaves(false)
        #expect(fixture.app.recordSetup(.sleepTarget, .skipped))
        #expect(SetupStep(stored: fixture.app.state.onboarding.setupStep) == .health)

        let before = UserDefaults.standard.stringArray(forKey: "assistant.selectedCalendars")
        fixture.assistant.calendars.toggle(.init(id: "fixture", provider: .apple, title: "Fixture", writable: false))
        #expect(UserDefaults.standard.stringArray(forKey: "assistant.selectedCalendars") == before)
    }

    @Test func galleryHealthRefusesEveryChoiceWithoutAsking() async {
        let fixture = GalleryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.app.load()
        for choice in [HealthChoice.readSleep, .readCaffeine, .writeCaffeine] {
            _ = await fixture.app.setHealthChoice(choice, enabled: true)
            #expect(!fixture.app.state.healthChoices[choice])
        }
    }
}
