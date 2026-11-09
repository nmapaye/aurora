import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// No model or Health calls: these seams exercise app persistence and lifecycle.
@MainActor
@Suite struct AppleOnDeviceFeatureTests {
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func app(_ directory: URL) -> AppModel {
        let app = AppModel(makeStore: { StateStore(directory: directory) }, legacy: { nil })
        app.load(); return app
    }
    func assistant() -> AssistantModel {
        AssistantModel(calendars: CalendarService(providers: [], defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }
    let input = "I had 80 mg tea now"
    let spans = LocalDrinkUnderstanding.Evidence(route: "log", drink: "tea", amount: "80 mg", time: "now")

    @Test func explicitSavePersistsSnapshotOnceAndExactUndoOnly() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        assistant.extractLocalDrink = { _ in self.spans }
        assistant.send(input, app: app)
        await assistant.waitForCurrentRequest()
        #expect(app.state.doses.isEmpty)
        let snapshot = try #require(assistant.pendingDraft)
        #expect(assistant.localDrinkReview.proposal?.provenance == "Typed amount · mg")
        #expect(!assistant.conversation.messages.contains { $0.text == input })
        assistant.saveDose(app: app); assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1)
        #expect(app.state.doses.first?.mg == 80 && app.state.doses.first?.timestamp == snapshot.timestamp)
        let reopened = try #require(try StateStore(directory: root).load())
        #expect(reopened.doses == app.state.doses)
        let receipt = try #require(assistant.conversation.messages.last)
        #expect(receipt.card?.state == .saved)
        assistant.undoReceipt(receipt, app: app); assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses.isEmpty)
        #expect(assistant.conversation.messages.last?.card?.state == .undone)
    }

    @Test func changedSnapshotFailsClosedAndDismissWritesNothing() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        assistant.extractLocalDrink = { _ in self.spans }
        assistant.send(input, app: app); await assistant.waitForCurrentRequest()
        assistant.pendingDraft?.mg = "999"
        assistant.saveDose(app: app)
        #expect(app.state.doses.isEmpty && assistant.failure != nil)
        assistant.discardDraft()
        #expect(assistant.pendingDraft == nil && app.state.doses.isEmpty)
    }

    @Test func failedPersistenceDoesNotAcknowledgeAndAllowsExplicitRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        assistant.extractLocalDrink = { _ in self.spans }
        assistant.send(input, app: app); await assistant.waitForCurrentRequest()
        try FileManager.default.removeItem(at: root)
        try Data("blocked".utf8).write(to: root)
        assistant.saveDose(app: app)
        #expect(app.state.doses.isEmpty && assistant.pendingDraft != nil && assistant.failure != nil)
        #expect(!assistant.conversation.messages.contains { $0.card?.kind == .receipt })
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        assistant.saveDose(app: app)
        #expect(app.state.doses.count == 1 && assistant.pendingDraft == nil)
    }

    @Test func cancellationRejectsLateModelResult() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        var finish: CheckedContinuation<LocalDrinkUnderstanding.Evidence, Never>?
        assistant.extractLocalDrink = { _ in await withCheckedContinuation { finish = $0 } }
        assistant.send(input, app: app)
        // Bounded scheduler yields to enter the injected suspension; no inference.
        for _ in 0..<20 where finish == nil { await Task.yield() }
        let continuation = try #require(finish)
        assistant.cancel()
        continuation.resume(returning: spans)
        for _ in 0..<20 { await Task.yield() }
        #expect(assistant.pendingDraft == nil && assistant.localDrinkReview.proposal == nil)
        #expect(app.state.doses.isEmpty)
    }

    @Test func modelMismatchAndUnavailableModelNeverFallThroughToRuleDraft() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        assistant.extractLocalDrink = { _ in .init(route: "log", drink: "tea", amount: "120 mg", time: "now") }
        assistant.send(input, app: app); await assistant.waitForCurrentRequest()
        #expect(assistant.pendingDraft == nil && app.state.doses.isEmpty)
        assistant.extractLocalDrink = { _ in throw AppleOnDeviceFeatures.FeatureFailure("Not ready. Manual Log caffeine still works.") }
        assistant.send(input, app: app); await assistant.waitForCurrentRequest()
        #expect(assistant.pendingDraft == nil && app.state.doses.isEmpty)
        #expect(assistant.conversation.messages.last?.text.contains("Manual Log caffeine") == true)
        assistant.send("Log caffeine", app: app); await assistant.waitForCurrentRequest()
        #expect(assistant.pendingDraft != nil && !assistant.reviewingLocalDrink)
    }

    @Test func explanationIntegratesCapturedCompositionAndLabeledRecovery() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        assistant.composeLocalExplanation = { bundle in
            "On-device composition · " + (try #require(bundle.render(bundle.allowedCompositions[0])))
        }
        assistant.send("How is my energy?", app: app); await assistant.waitForCurrentRequest()
        #expect(assistant.conversation.messages.last?.card?.summary.hasPrefix("On-device composition") == true)
        assistant.composeLocalExplanation = { _ in throw AppleOnDeviceFeatures.FeatureFailure("Not ready") }
        assistant.send("How is my energy?", app: app); await assistant.waitForCurrentRequest()
        #expect(assistant.conversation.messages.last?.card?.summary.hasPrefix("Deterministic summary") == true)
        #expect(assistant.conversation.messages.last?.card?.summary.contains("No record") == true)
    }
    @Test func failedUndoRetainsLocalRecordAndSavedReceipt() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        assistant.extractLocalDrink = { _ in self.spans }
        assistant.send(input, app: app); await assistant.waitForCurrentRequest()
        assistant.saveDose(app: app)
        let receipt = try #require(assistant.conversation.messages.last)
        let saved = app.state.doses
        try FileManager.default.removeItem(at: root)
        try Data("blocked".utf8).write(to: root)
        assistant.undoReceipt(receipt, app: app)
        #expect(app.state.doses == saved && assistant.failure != nil)
        #expect(assistant.conversation.messages.last?.card?.state == .saved)
    }

    @Test func overlongInputIsNotTruncatedIntoAnApparentlySafeRequest() async {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        var called = false
        assistant.extractLocalDrink = { _ in called = true; return self.spans }
        assistant.send(input + String(repeating: " ", count: 2100) + "do not log", app: app)
        await assistant.waitForCurrentRequest()
        #expect(!called && assistant.pendingDraft == nil && app.state.doses.isEmpty)
    }

    @Test func knownRouterPrecedencePreservesCaffeineQuestionsAndOtherCapabilities() async {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        var drinkCalls = 0
        assistant.extractLocalDrink = { _ in drinkCalls += 1; return self.spans }
        let cases: [(String, AssistantCard.Kind)] = [
            ("caffeine cutoff scenario", .cutoffScenario),
            ("What is my caffeine cutoff?", .cutoffScenario),
            ("Export my caffeine records", .exports),
            ("Show my coffee history", .history),
            ("How much coffee should I drink?", .clarification),
            ("Should I drink coffee?", .clarification)
        ]
        for (input, kind) in cases {
            assistant.send(input, app: app); await assistant.waitForCurrentRequest()
            #expect(assistant.conversation.messages.last?.card?.kind == kind)
            #expect(assistant.pendingDraft == nil)
        }
        #expect(drinkCalls == 0 && app.state.doses.isEmpty)
        assistant.send(input, app: app); await assistant.waitForCurrentRequest()
        #expect(drinkCalls == 1 && assistant.reviewingLocalDrink && app.state.doses.isEmpty)
    }

    @Test func renderedEnergyCardIncludesSelectedActualEstimatorContribution() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = app(root), assistant = assistant()
        app.addManualSleep(.init(start: app.now - 9 * hourMs, end: app.now - 2 * hourMs, note: ""))
        assistant.composeLocalExplanation = { bundle in
            let factor = try #require(bundle.factors.first { $0.kind == .sleepDebt })
            let composition = try #require(bundle.allowedCompositions.first { $0.contains(factor.placeholder) })
            return "On-device composition · " + (try #require(bundle.render(composition)))
        }
        assistant.send("How is my energy?", app: app); await assistant.waitForCurrentRequest()
        let card = try #require(assistant.conversation.messages.last?.card)
        let part = try #require(card.energy?.estimate.contributions.first { $0.kind == .sleepDebt })
        #expect(card.summary.contains("recorded-sleep debt term contributes " + part.pointsText + " points"))
        #expect(card.summary.contains("unclamped model"))
        #expect(card.summary.hasPrefix("On-device composition"))
        #expect(card.summary.range(of: #"\[factor_"#, options: .regularExpression) == nil)
    }

}
