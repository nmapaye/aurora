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

    @Test func removalsAndClearsMoveNothing() {
        let list = messages(2)
        #expect(ConversationReveal.after(list, previousCount: 2, readingLatest: true) == .none)
        #expect(ConversationReveal.after(list, previousCount: 5, readingLatest: false) == .none)
        #expect(ConversationReveal.after([], previousCount: 3, readingLatest: true) == .none)
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
