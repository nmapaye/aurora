import AuroraCore
import Foundation
import Testing
@testable import Aurora

/// AppModel with an injected Health provider: local saves come first,
/// Health outcomes persist across relaunch, and erase discards late work.
@MainActor
@Suite struct HealthSyncAppTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-health-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeModel(health: ScriptedHealth) -> AppModel {
        let directory = root.appendingPathComponent("Support/Aurora", isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        let model = AppModel(
            clock: LocalClock(timeZone: TimeZone(identifier: "America/Los_Angeles")!),
            health: health,
            makeStore: { StateStore(directory: directory) },
            legacy: { LegacyImport(documents: docs) }
        )
        model.load()
        return model
    }

    private func draft(_ mg: String) -> CustomDoseDraft {
        CustomDoseDraft(mg: mg, source: "Drip", timestamp: AppModel.currentMillis() - 60_000, note: "")
    }

    @Test func exportOutcomesAreSeparateAndSurviveRelaunch() async throws {
        let health = ScriptedHealth()
        let model = makeModel(health: health)
        model.completeOnboarding()
        #expect(await model.setHealthChoice(.writeCaffeine, enabled: true) == .requested)
        #expect(health.authorizations.last?.write == [.caffeine] && health.authorizations.last?.read.isEmpty == true)

        health.failSaves = true
        let dose = model.addCustomDose(draft("95"))
        #expect(model.mutationFailure == nil && model.state.doses.map(\.id) == [dose.id])
        await model.healthSync.runPendingActions()
        #expect(model.healthStatus(forDoseID: dose.id).needsAttention)

        let relaunched = makeModel(health: health)
        #expect(relaunched.state.doses.map(\.id) == [dose.id])
        #expect(relaunched.healthStatus(forDoseID: dose.id).needsAttention)
        health.failSaves = false
        await relaunched.retryHealthExports()
        #expect(relaunched.healthStatus(forDoseID: dose.id) == .exported)
        #expect(health.savedSyncIdentifiers == [HealthOrigin.syncIdentifier(forDoseID: dose.id)])

        relaunched.undo(try #require(relaunched.state.doses.first))
        #expect(relaunched.state.doses.isEmpty)
        await relaunched.healthSync.runPendingActions()
        #expect(relaunched.healthStatus(forDoseID: dose.id) == .removed)
        #expect(health.deletedSyncIdentifiers == [HealthOrigin.syncIdentifier(forDoseID: dose.id)])
    }

    @Test func deleteAllDuringAReadDiscardsTheLateResult() async throws {
        let health = ScriptedHealth()
        health.caffeine = [HealthCaffeineSample(
            provenance: HealthSampleProvenance(sampleUUID: "third-party", sourceBundleIdentifier: "com.example.tracker"),
            timestamp: AppModel.currentMillis() - 60_000, mg: 80
        )]
        let model = makeModel(health: health)
        model.completeOnboarding()
        #expect(await model.setHealthChoice(.readCaffeine, enabled: true) == .requested)
        #expect(model.state.doses.count == 1)

        health.holdReads = true
        let refresh = Task { await model.refresh(.explicit) }
        while !health.readWaiting { await Task.yield() }
        model.deleteAllData()
        health.releaseRead()
        await refresh.value
        // Let the released read land before checking it was discarded.
        for _ in 0..<50 { await Task.yield() }
        #expect(model.state.doses.isEmpty)
        #expect(model.state.healthLedger == .empty)
        // The choice stays; the next read imports Health's records again.
        #expect(model.state.healthChoices.readCaffeine)
    }

    @Test func anchoredSleepKeepsSampleIdentityThroughConnect() async throws {
        let end = AppModel.currentMillis() - 60_000
        let provider = AnchoredSleepHealth(samples: [
            HealthSleepSample(start: end - 7 * hourMs, end: end, provenance: HealthSampleProvenance(sampleUUID: "W", sourceBundleIdentifier: "com.apple.health")),
            HealthSleepSample(start: end - 7 * hourMs, end: end, provenance: HealthSampleProvenance(sampleUUID: "P", sourceBundleIdentifier: "com.example.sleep")),
        ])
        let directory = root.appendingPathComponent("Support/Aurora", isDirectory: true)
        let model = AppModel(health: provider, makeStore: { StateStore(directory: directory) }, legacy: { nil })
        model.load()
        await model.connectHealth()
        #expect(Set(model.state.sleeps.map(\.id)) == [RecordID.healthSleepID(sampleUUID: "w"), RecordID.healthSleepID(sampleUUID: "p")])
        #expect(model.state.healthSync.importStatus == .succeeded && model.state.healthSync.importedCount == 1)
        #expect(model.state.healthLedger.anchor(for: .sleepAnalysis) != nil)
    }

    @Test func receiptsReportHealthApartFromTheLocalSave() async throws {
        let health = ScriptedHealth()
        let model = makeModel(health: health)
        model.completeOnboarding()
        _ = await model.setHealthChoice(.writeCaffeine, enabled: true)
        let assistant = AssistantModel(makeStore: { ConversationStore(directory: root.appendingPathComponent("Support/Aurora", isDirectory: true)) })
        let dose = model.addCustomDose(draft("60"))
        assistant.receipt(recordID: dose.id, kind: "caffeine", app: model, title: "Caffeine saved")
        let card = try #require(assistant.conversation.messages.last?.card)
        #expect(card.title == "Caffeine saved")
        let health0 = try #require(card.metrics.first { $0.id == "health" })
        #expect(health0.label == "Apple Health" && health0.value == "Export pending")
        await model.healthSync.runPendingActions()
        for _ in 0..<50 where assistant.conversation.messages.last?.card?.metrics.first(where: { $0.id == "health" })?.value != "Added" {
            await Task.yield()
        }
        #expect(assistant.conversation.messages.last?.card?.metrics.first { $0.id == "health" }?.value == "Added")
    }
}

private struct AnchoredSleepHealth: HealthDataProvider {
    let samples: [HealthSleepSample]
    var capabilities: HealthCapabilities { [.authorization, .readSleep, .readSleepChanges] }
    var isAvailable: Bool { true }
    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {}
    func sleepChanges(after anchor: Data?) async throws -> HealthSleepChanges {
        HealthSleepChanges(added: anchor == nil ? samples : [], deletedSampleUUIDs: [], anchor: Data("1".utf8))
    }
}

/// Scripted Health: records requests, fails saves on demand, and can hold a
/// caffeine read until released.
final class ScriptedHealth: HealthDataProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorizations: [(read: Set<HealthDataKind>, write: Set<HealthDataKind>)] = []
    private var _saved: [String] = []
    private var _deleted: [String] = []
    private var _failSaves = false
    private var _caffeine: [HealthCaffeineSample] = []
    private var _holdReads = false
    private var held: CheckedContinuation<Void, Never>?

    var capabilities: HealthCapabilities { [.authorization, .readSleep, .readCaffeineChanges, .writeOwnCaffeine, .deleteOwnCaffeine] }
    var isAvailable: Bool { true }
    var authorizations: [(read: Set<HealthDataKind>, write: Set<HealthDataKind>)] { lock.withLock { _authorizations } }
    var savedSyncIdentifiers: [String] { lock.withLock { _saved } }
    var deletedSyncIdentifiers: [String] { lock.withLock { _deleted } }
    var failSaves: Bool {
        get { lock.withLock { _failSaves } }
        set { lock.withLock { _failSaves = newValue } }
    }
    var caffeine: [HealthCaffeineSample] {
        get { lock.withLock { _caffeine } }
        set { lock.withLock { _caffeine = newValue } }
    }
    var holdReads: Bool {
        get { lock.withLock { _holdReads } }
        set { lock.withLock { _holdReads = newValue } }
    }
    var readWaiting: Bool { lock.withLock { held != nil } }

    func releaseRead() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            _holdReads = false
            defer { held = nil }
            return held
        }
        continuation?.resume()
    }

    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        lock.withLock { _authorizations.append((read, write)) }
    }

    func sleepSamples(from start: Millis, to end: Millis) async throws -> [HealthSleepSample] { [] }

    func caffeineChanges(after anchor: Data?) async throws -> HealthCaffeineChanges {
        if holdReads {
            await withCheckedContinuation { continuation in lock.withLock { held = continuation } }
        }
        return HealthCaffeineChanges(added: anchor == nil ? caffeine : [], deletedSampleUUIDs: [], anchor: Data("1".utf8))
    }

    func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String {
        try lock.withLock {
            if _failSaves { throw HealthKitService.Failure.notAllowed }
            _saved.append(write.syncIdentifier)
            return "sample-\(_saved.count)"
        }
    }

    func deleteOwnCaffeine(syncIdentifier: String) async throws {
        lock.withLock { _deleted.append(syncIdentifier) }
    }

    func ownCaffeineSample(syncIdentifier: String) async throws -> HealthSampleProvenance? { nil }
}
