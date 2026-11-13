import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// Authored native fixtures; no model generation or system Health writes.
@MainActor
@Suite struct CaffeineReviewShortcutAppTests {
    func app(_ root: URL) -> AppModel {
        let app = AppModel(makeStore: { StateStore(directory: root) }, legacy: { nil })
        app.load(); app.completeOnboarding()
        return app
    }
    func assistant() -> AssistantModel {
        AssistantModel(calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }
    @Test func onlyOpensReviewThenExplicitSavePersistsOnceAndUndoTargetsThatRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        var request = CaffeineReviewShortcut(); request.request(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(app.state.doses.isEmpty && assistant.pendingDraft != nil && !request.requested)
        let count = assistant.conversation.messages.count
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(assistant.conversation.messages.count == count && app.state.doses.isEmpty)
        assistant.pendingDraft?.mg = "80"; assistant.pendingDraft?.source = "Tea"
        assistant.saveDose(app: app); assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1)
        let reopened = try #require(try StateStore(directory: root).load())
        #expect(reopened.doses == app.state.doses)
        let receipt = try #require(assistant.conversation.messages.last)
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
    }
    @Test func existingReviewAndProcessingArePreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        assistant.send("Log caffeine", app: app); await assistant.waitForCurrentRequest()
        assistant.pendingDraft?.mg = "88"
        let draft = assistant.pendingDraft, count = assistant.conversation.messages.count
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(assistant.pendingDraft == draft && assistant.conversation.messages.count == count)
        #expect(app.state.doses.isEmpty && !request.requested)
        assistant.discardDraft(); assistant.processing = true; request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(assistant.processing && assistant.pendingDraft == nil && app.state.doses.isEmpty && !request.requested)
    }
    @Test func backgroundRequestWaitsForForegroundWithoutWriting() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        await assistant.start(app: app)
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: false, coveringWork: false)
        #expect(request.requested && assistant.pendingDraft == nil && app.state.doses.isEmpty)
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(!request.requested && assistant.pendingDraft != nil && app.state.doses.isEmpty)
    }
    @Test func unopenedConversationCannotConsumeOrWrite() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: false)
        #expect(request.requested && assistant.pendingDraft == nil && app.state.doses.isEmpty)
    }
    @Test func routerReactionCoverPreservedWithoutHiddenReviewOrReplay() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant(), router = Router()
        await assistant.start(app: app)
        let messages = assistant.conversation.messages
        router.open(.reactionTest)
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true,
                                        coveringWork: router.coversCaffeineReview)
        #expect(router.showReactionTest && !request.requested)
        #expect(assistant.pendingDraft == nil && assistant.pendingMessageID == nil)
        #expect(assistant.conversation.messages == messages && app.state.doses.isEmpty)
        router.showReactionTest = false
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true,
                                        coveringWork: router.coversCaffeineReview)
        #expect(assistant.pendingDraft == nil && assistant.pendingMessageID == nil)
        #expect(assistant.conversation.messages == messages && app.state.doses.isEmpty)
    }
    @Test func actualHealthSheetOwnerPreservedEvenBeforeForegroundAndNeverReplayed() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant(), router = Router()
        await assistant.start(app: app)
        let messages = assistant.conversation.messages
        // Same canonical state bound to the actual Health sheet AND composer.
        router.showHealthConnection = true
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: false,
                                        coveringWork: router.coversCaffeineReview)
        #expect(router.showHealthConnection && !request.requested)
        #expect(assistant.pendingDraft == nil && assistant.pendingMessageID == nil)
        #expect(assistant.conversation.messages == messages && app.state.doses.isEmpty)
        router.showHealthConnection = false
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true,
                                        coveringWork: router.coversCaffeineReview)
        #expect(assistant.pendingDraft == nil && assistant.pendingMessageID == nil)
        #expect(assistant.conversation.messages == messages && app.state.doses.isEmpty)
    }
    /// The one-time Terms prompt for an existing install covers the
    /// conversation: a Shortcut request then opens no hidden review, and
    /// dismissing the prompt never replays it.
    /// What AssistantView passes as covering work.
    func covering(_ router: Router, _ app: AppModel) -> Bool {
        router.coversCaffeineReview || TermsUpdatePrompt.coversWork(app.state.onboarding)
    }
    @Test func termsUpdatePromptCoversWithoutHiddenReviewOrReplay() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant(), router = Router()
        await assistant.start(app: app)
        // Onboarded with no Terms acknowledgement, as on a pre-Terms install.
        #expect(app.state.onboarding.needsTermsAcknowledgement())
        let messages = assistant.conversation.messages
        // Covered before the sheet is drawn (welcome still up) and while it shows.
        for showing in [false, true] {
            router.showTermsUpdate = showing
            #expect(covering(router, app))
            var request = CaffeineReviewShortcut(); request.request()
            assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: covering(router, app))
            #expect(!request.requested)
            #expect(assistant.pendingDraft == nil && assistant.pendingMessageID == nil)
            #expect(assistant.conversation.messages == messages && app.state.doses.isEmpty)
        }
        #expect(app.acknowledgeTerms())
        router.showTermsUpdate = false
        #expect(!covering(router, app))
        var later = CaffeineReviewShortcut()
        assistant.reviewCaffeineShortcut(&later, app: app, foreground: true, coveringWork: covering(router, app))
        // The request made behind the sheet isn't replayed after Continue.
        #expect(assistant.pendingDraft == nil && assistant.conversation.messages == messages && app.state.doses.isEmpty)
        #expect(!app.state.onboarding.needsTermsAcknowledgement())
    }
    /// An unsaved draft behind the sheet is neither lost nor saved, and a
    /// Shortcut request then doesn't replace it.
    @Test func unsavedDraftSurvivesTheTermsSheetUnsaved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant(), router = Router()
        await assistant.start(app: app)
        assistant.send("Log caffeine", app: app); await assistant.waitForCurrentRequest()
        assistant.pendingDraft?.mg = "88"
        let draft = try #require(assistant.pendingDraft)
        let count = assistant.conversation.messages.count
        router.showTermsUpdate = true
        var request = CaffeineReviewShortcut(); request.request()
        assistant.reviewCaffeineShortcut(&request, app: app, foreground: true, coveringWork: covering(router, app))
        #expect(assistant.pendingDraft == draft && assistant.conversation.messages.count == count)
        #expect(app.state.doses.isEmpty && !request.requested)
        #expect(app.acknowledgeTerms())
        router.showTermsUpdate = false
        #expect(assistant.pendingDraft == draft && app.state.doses.isEmpty)
        let reopened = try #require(try StateStore(directory: root).load())
        #expect(reopened.doses.isEmpty && reopened.onboarding.termsAcceptedVersion == LegalCopy.version)
        // Saving stays the person's own tap.
        assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1 && app.state.doses.first?.mg == 88)
    }
}
