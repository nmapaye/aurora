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

    /// CI (main, 73199d4): "Show my energy curve" and its card were added in
    /// one update, so the conversation went to the end and the long card's
    /// title sat under the navigation bar.
    @Test func aSentMessageAndItsReplyInOneUpdateShowTheReplysStart() {
        let list = messages(5, userAt: [3])
        #expect(ConversationReveal.after(list, previousCount: 3, readingLatest: true) == .start(list[4].id))
        #expect(ConversationReveal.after(list, previousCount: 3, readingLatest: false) == .start(list[4].id))
        // Several replies after the message: the first of them.
        let two = messages(6, userAt: [3])
        #expect(ConversationReveal.after(two, previousCount: 3, readingLatest: true) == .start(two[4].id))
        // An earlier reply and a later message in the same update: the end.
        let replyThenSent = messages(5, userAt: [4])
        #expect(ConversationReveal.after(replyThenSent, previousCount: 3, readingLatest: true) == .end)
    }

    /// testLongCardArrivesShowingItsStart, CI run 40077271377: the sent
    /// message showed the end, the card arrived in its own update and showed
    /// its start, then the bottom area grew as the keyboard finished hiding.
    /// On iOS 18 the end still read as on screen, so the conversation went
    /// to the end of the card and its title sat under the navigation bar.
    @Test func aTallerBottomAreaKeepsTheRevealedReplysStart() {
        let list = messages(5, userAt: [3])
        var follow = ConversationFollow()
        follow.revealed(ConversationReveal.after(Array(list.prefix(4)), previousCount: 3, readingLatest: true))
        follow.revealed(ConversationReveal.after(list, previousCount: 4, readingLatest: true))
        #expect(follow.afterBottomAreaGrew(from: 196, to: 196.33, atEnd: true, holding: false) == .start(list[4].id))
        #expect(follow.afterBottomAreaGrew(from: 196, to: 252, atEnd: true, holding: false) == .start(list[4].id))
        // Once the person scrolls, the end they reach is theirs to keep.
        follow.stopFollowing()
        #expect(follow.afterBottomAreaGrew(from: 196, to: 252, atEnd: true, holding: false) == .end)
    }

    @Test func aTallerBottomAreaKeepsTheEndOnlyWhenItWasShown() {
        var follow = ConversationFollow()
        follow.revealed(.start(UUID()))
        follow.revealed(.end)
        #expect(follow.afterBottomAreaGrew(from: 196, to: 252, atEnd: true, holding: false) == .end)
        #expect(follow.afterBottomAreaGrew(from: 252, to: 196, atEnd: true, holding: false) == .none)
        #expect(follow.afterBottomAreaGrew(from: 196, to: 252, atEnd: false, holding: false) == .none)
        #expect(follow.afterBottomAreaGrew(from: 196, to: 252, atEnd: true, holding: true) == .none)
        // A held message doesn't change what is followed.
        follow.revealed(.hold(UUID()))
        #expect(follow.afterBottomAreaGrew(from: 196, to: 252, atEnd: true, holding: false) == .end)
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
