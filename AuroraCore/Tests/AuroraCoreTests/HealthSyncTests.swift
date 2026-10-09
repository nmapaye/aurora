import Foundation
import Testing
@testable import AuroraCore

private let base: Millis = 1_790_527_260_000 // 2026-09-27 16:41 UTC

// MARK: Test doubles

/// Suspends a provider call until the test opens it, so races are explicit.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var arrived = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready: [CheckedContinuation<Void, Never>]? = lock.withLock {
                if opened { return nil }
                waiting.append(continuation)
                arrived = true
                defer { arrivals = [] }
                return arrivals
            }
            guard let ready else { continuation.resume(); return }
            ready.forEach { $0.resume() }
        }
    }

    /// Returns once a call is held at the gate.
    func arrival() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now = lock.withLock {
                if arrived { return true }
                arrivals.append(continuation)
                return false
            }
            if now { continuation.resume() }
        }
    }

    func open() {
        let held = lock.withLock {
            opened = true
            defer { waiting = [] }
            return waiting
        }
        held.forEach { $0.resume() }
    }
}

struct FakeFailure: LocalizedError, Equatable {
    var text: String
    var errorDescription: String? { text }
}

/// An in-memory Health store with anchored change history, source bundles
/// and HealthKit's sync-identifier rule (a save replaces Aurora's sample
/// with the same identifier only at a higher version).
final class FakeHealth: HealthDataProvider, @unchecked Sendable {
    private struct Event { var seq: Int; var added: HealthCaffeineSample?; var deleted: String? }

    private let lock = NSLock()
    private var _capabilities: HealthCapabilities = [.authorization, .readSleep, .readCaffeineChanges, .writeOwnCaffeine, .deleteOwnCaffeine, .observeChanges]
    private var _available = true
    private var samples: [HealthCaffeineSample] = []
    private var events: [Event] = []
    private var seq = 0
    private var nextUUID = 0
    private var handlers: [String: (kind: HealthDataKind, onChange: @Sendable (HealthDataKind) async -> Void)] = [:]
    private var _calls: [String] = []
    private var _authorizations: [(read: Set<HealthDataKind>, write: Set<HealthDataKind>)] = []
    private var _completions = 0
    private var failures: [String: [Error]] = [:]
    private var gates: [String: Gate] = [:]
    private var _landThenFailSave = false

    var capabilities: HealthCapabilities {
        get { lock.withLock { _capabilities } }
        set { lock.withLock { _capabilities = newValue } }
    }
    var isAvailable: Bool {
        get { lock.withLock { _available } }
        set { lock.withLock { _available = newValue } }
    }
    var calls: [String] { lock.withLock { _calls } }
    var authorizations: [(read: Set<HealthDataKind>, write: Set<HealthDataKind>)] { lock.withLock { _authorizations } }
    var completions: Int { lock.withLock { _completions } }
    var activeObservers: Set<HealthDataKind> { lock.withLock { Set(handlers.values.map(\.kind)) } }
    var stored: [HealthCaffeineSample] { lock.withLock { samples } }
    var ownStored: [HealthCaffeineSample] { stored.filter { $0.provenance.sourceBundleIdentifier == HealthOrigin.appBundleIdentifier } }

    func fail(_ operation: String, with error: Error) { lock.withLock { failures[operation, default: []].append(error) } }
    func hold(_ operation: String) -> Gate { lock.withLock { let gate = Gate(); gates[operation] = gate; return gate } }
    func landThenFailNextSave() { lock.withLock { _landThenFailSave = true } }

    func add(_ uuid: String, source: String = "com.example.tracker", at timestamp: Millis, mg: Double, syncIdentifier: String? = nil, syncVersion: Int? = nil) {
        lock.withLock {
            insert(HealthCaffeineSample(
                provenance: HealthSampleProvenance(sampleUUID: uuid, sourceBundleIdentifier: source, syncIdentifier: syncIdentifier, syncVersion: syncVersion),
                timestamp: timestamp, mg: mg
            ))
        }
    }

    func delete(_ uuid: String) { lock.withLock { remove(uuid.lowercased()) } }

    private func insert(_ sample: HealthCaffeineSample) {
        samples.append(sample)
        seq += 1
        events.append(Event(seq: seq, added: sample))
    }

    private func remove(_ uuid: String) {
        guard samples.contains(where: { $0.provenance.sampleUUID == uuid }) else { return }
        samples.removeAll { $0.provenance.sampleUUID == uuid }
        seq += 1
        events.append(Event(seq: seq, deleted: uuid))
    }

    private func begin(_ operation: String) async throws {
        let gate = lock.withLock { () -> Gate? in
            _calls.append(operation)
            return gates.removeValue(forKey: operation)
        }
        await gate?.pass()
        if let error = lock.withLock({ () -> Error? in
            guard var queue = failures[operation], !queue.isEmpty else { return nil }
            let error = queue.removeFirst()
            failures[operation] = queue
            return error
        }) { throw error }
    }

    func requestAuthorization(read: Set<HealthDataKind>, write: Set<HealthDataKind>) async throws {
        lock.withLock { _authorizations.append((read, write)) }
        try await begin("authorization")
    }

    func caffeineChanges(after anchor: Data?) async throws -> HealthCaffeineChanges {
        try await begin("read")
        return lock.withLock {
            let from = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
            let later = events.filter { $0.seq > from }
            let present = Set(samples.map(\.provenance.sampleUUID))
            return HealthCaffeineChanges(
                added: later.compactMap(\.added).filter { present.contains($0.provenance.sampleUUID) },
                deletedSampleUUIDs: later.compactMap(\.deleted),
                anchor: Data(String(seq).utf8)
            )
        }
    }

    func saveOwnCaffeine(_ write: HealthCaffeineWrite) async throws -> String {
        try await begin("save")
        let (uuid, failAfter) = lock.withLock { () -> (String, Bool) in
            let failAfter = _landThenFailSave
            _landThenFailSave = false
            if let existing = samples.first(where: { isOwn($0) && $0.provenance.syncIdentifier == write.syncIdentifier }) {
                if (existing.provenance.syncVersion ?? 0) >= write.syncVersion { return (existing.provenance.sampleUUID, failAfter) }
                remove(existing.provenance.sampleUUID)
            }
            nextUUID += 1
            let uuid = "aurora-\(nextUUID)"
            insert(HealthCaffeineSample(
                provenance: HealthSampleProvenance(
                    sampleUUID: uuid, sourceBundleIdentifier: HealthOrigin.appBundleIdentifier,
                    syncIdentifier: write.syncIdentifier, syncVersion: write.syncVersion
                ),
                timestamp: write.timestamp, mg: write.mg
            ))
            return (uuid, failAfter)
        }
        if failAfter { throw FakeFailure(text: "Health didn’t answer.") }
        return uuid
    }

    func deleteOwnCaffeine(syncIdentifier: String) async throws {
        try await begin("delete")
        lock.withLock {
            for sample in samples where isOwn(sample) && sample.provenance.syncIdentifier == syncIdentifier {
                remove(sample.provenance.sampleUUID)
            }
        }
    }

    func ownCaffeineSample(syncIdentifier: String) async throws -> HealthSampleProvenance? {
        try await begin("lookup")
        return lock.withLock { samples.first { isOwn($0) && $0.provenance.syncIdentifier == syncIdentifier }?.provenance }
    }

    func startObserving(_ kinds: Set<HealthDataKind>, onChange: @escaping @Sendable (HealthDataKind) async -> Void) async throws -> HealthObservation {
        try await begin("observe")
        let observation = HealthObservation(id: UUID().uuidString, kinds: kinds)
        lock.withLock { handlers[observation.id] = (kinds.first!, onChange) }
        return observation
    }

    func stopObserving(_ observation: HealthObservation) {
        lock.withLock { _ = handlers.removeValue(forKey: observation.id) }
    }

    /// Delivers a change the way HealthKit does, then completes it.
    func fire(_ kind: HealthDataKind) async {
        let targets = lock.withLock { handlers.values.filter { $0.kind == kind }.map(\.onChange) }
        for onChange in targets {
            await onChange(kind)
            lock.withLock { _completions += 1 }
        }
    }

    private func isOwn(_ sample: HealthCaffeineSample) -> Bool {
        sample.provenance.sourceBundleIdentifier == HealthOrigin.appBundleIdentifier
    }
}

/// Stands in for AppModel: an in-memory state saved on every commit, with
/// a switch to make saves fail.
@MainActor
final class Harness {
    var state = AppState()
    /// What a relaunch would read.
    var saved = AppState()
    var failCommits = false
    var now: Millis = base
    private var ids = 0

    init(_ setup: (inout AppState) -> Void = { _ in }) {
        setup(&state)
        saved = state
    }

    var host: HealthSyncEngine.Host {
        HealthSyncEngine.Host(
            state: { self.state },
            commit: { change in
                var next = self.state
                change(&next)
                guard !self.failCommits else { return false }
                self.state = next
                self.saved = next
                return true
            },
            now: { self.now },
            newActionID: { self.ids += 1; return "action-\(self.ids)" }
        )
    }

    func engine(_ provider: FakeHealth) -> HealthSyncEngine {
        HealthSyncEngine(provider: provider, host: host)
    }

    func newID() -> String { ids += 1; return "action-\(ids)" }

    /// Local save first, with the export queued in the same change, as
    /// AppModel does.
    @discardableResult
    func saveDose(_ id: String, mg: Double, at timestamp: Millis) -> Bool {
        host.commit {
            $0.addDose(Dose(id: id, timestamp: timestamp, mg: mg, source: "Drip"))
            $0.queueHealthSave(doseID: id, now: self.now, id: self.newID())
        }
    }

    @discardableResult
    func correctDose(_ id: String, mg: Double) -> Bool {
        let dose = state.doses.first { $0.id == id }!
        return host.commit {
            $0.updateDose(id: id, timestamp: dose.timestamp, mg: mg, source: dose.source, note: dose.note)
            $0.queueHealthCorrection(doseID: id, now: self.now, id: self.newID())
        }
    }

    @discardableResult
    func removeDose(_ id: String) -> Bool {
        host.commit {
            $0.removeDose(id: id)
            $0.queueHealthRemoval(doseID: id, now: self.now, id: self.newID())
        }
    }

    /// Full erase as AppModel performs it.
    func erase(_ engine: HealthSyncEngine) {
        engine.invalidateAll()
        state = AppState()
        saved = state
    }
}

private func exporting(_ state: inout AppState) {
    state.healthChoices = HealthChoices(writeCaffeine: true)
}

private func reading(_ state: inout AppState) {
    state.healthChoices = HealthChoices(readCaffeine: true)
}

// MARK: Choices and permissions

@MainActor
@Suite struct HealthChoiceTests {
    @Test func eachChoiceRequestsOnlyItsOwnPermission() async {
        let health = FakeHealth()
        let harness = Harness()
        let engine = harness.engine(health)
        #expect(await engine.setChoice(.readCaffeine, enabled: true) == .requested)
        #expect(harness.state.healthChoices == HealthChoices(readCaffeine: true))
        #expect(await engine.setChoice(.writeCaffeine, enabled: true) == .requested)
        #expect(harness.state.healthChoices == HealthChoices(readCaffeine: true, writeCaffeine: true))
        #expect(await engine.setChoice(.readSleep, enabled: true) == .requested)
        let requests = health.authorizations
        #expect(requests.count == 3)
        #expect(requests[0].read == [.caffeine] && requests[0].write.isEmpty)
        #expect(requests[1].read.isEmpty && requests[1].write == [.caffeine])
        #expect(requests[2].read == [.sleepAnalysis] && requests[2].write.isEmpty)
        #expect(await engine.setChoice(.readCaffeine, enabled: false) == .turnedOff)
        #expect(harness.state.healthChoices == HealthChoices(readSleep: true, writeCaffeine: true))
    }

    @Test func refusedUnavailableOrUnsupportedRequestsLeaveTheChoiceOff() async {
        let health = FakeHealth()
        health.fail("authorization", with: FakeFailure(text: "Sheet dismissed."))
        let harness = Harness()
        let engine = harness.engine(health)
        #expect(await engine.setChoice(.writeCaffeine, enabled: true) == .failed("Sheet dismissed."))
        health.isAvailable = false
        #expect(await engine.setChoice(.readCaffeine, enabled: true) == .unavailable)
        health.isAvailable = true
        health.capabilities = [.authorization, .readSleep]
        #expect(await engine.setChoice(.writeCaffeine, enabled: true) == .unsupported)
        #expect(harness.state.healthChoices == .off)
    }

    @Test func sampleDataAndANewerLedgerNeverTouchHealth() async {
        let health = FakeHealth()
        let sample = Harness { $0.demoMode = true; $0.healthChoices = HealthChoices(readCaffeine: true, writeCaffeine: true) }
        let engine = sample.engine(health)
        #expect(await engine.setChoice(.readCaffeine, enabled: true) == .sampleData)
        #expect(await engine.readCaffeineChanges() == .skipped)
        sample.saveDose("d1", mg: 95, at: base - hourMs)
        #expect(sample.state.healthLedger.pendingActions.isEmpty)
        await engine.startObservers()

        let future = Harness { $0.healthLedger.version = 99; $0.healthChoices = HealthChoices(readCaffeine: true, writeCaffeine: true) }
        let paused = future.engine(health)
        #expect(await paused.setChoice(.writeCaffeine, enabled: true) == .paused)
        #expect(await paused.readCaffeineChanges() == .skipped)
        future.saveDose("d1", mg: 95, at: base - hourMs)
        #expect(future.state.healthLedger.pendingActions.isEmpty)
        #expect(health.calls.isEmpty && health.activeObservers.isEmpty)
    }

    @Test func aNewerLedgerVersionSurvivesARoundTrip() throws {
        var ledger = HealthSyncLedger()
        ledger.version = 99
        let decoded = try JSONDecoder().decode(HealthSyncLedger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded.version == 99 && !decoded.isSupported)
    }

    @Test func olderStatesCarryTheSleepRequestOverAsTheSleepChoice() throws {
        let granted = Data(#"{"schemaVersion":2,"onboarding":{"completed":true,"source":"healthkit","permissionStatus":"granted","appWalkthroughCompleted":true,"appWalkthroughStep":0}}"#.utf8)
        #expect(try JSONDecoder().decode(AppState.self, from: granted).healthChoices == HealthChoices(readSleep: true))
        let manual = Data(#"{"schemaVersion":2}"#.utf8)
        #expect(try JSONDecoder().decode(AppState.self, from: manual).healthChoices == .off)
        var state = AppState()
        state.healthChoices = HealthChoices(readCaffeine: true, writeCaffeine: true)
        #expect(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state)) == state)
        // A pending action stored before `startedAt` existed still decodes.
        let action = Data(#"{"id":"a","kind":"saveCaffeine","doseID":"d","syncIdentifier":"s","syncVersion":1,"createdAt":0,"attempts":0}"#.utf8)
        #expect(try JSONDecoder().decode(HealthPendingAction.self, from: action).startedAt == nil)
    }

    @Test func choiceAndStatusCopyNeverClaimsAccessOrPrescribes() {
        var texts = HealthChoice.allCases.flatMap { [$0.title, $0.detail, $0.requestedNote] }
        let statuses: [HealthExportStatus] = [
            .notExported, .pending(.saveCaffeine), .pending(.deleteCaffeine), .failed(.saveCaffeine, "x"),
            .failed(.deleteCaffeine, nil), .exported, .outdated, .keptInHealth, .removed, .cancelled, .uncertain,
        ]
        texts += statuses.flatMap { [$0.value ?? "", $0.detail] }
        for text in texts {
            #expect(CopyRules.violations(in: text).isEmpty, "\(text)")
            #expect(!text.lowercased().contains("granted") && !text.lowercased().contains("denied"), "\(text)")
            #expect(!text.contains("Saved to Apple Health") && !text.contains("saved to Health"), "\(text)")
        }
    }
}

// MARK: Anchored reads

@MainActor
@Suite struct HealthCaffeineReadTests {
    @Test func anEmptyReadIsJustEmpty() async throws {
        let health = FakeHealth()
        let harness = Harness(reading)
        let engine = harness.engine(health)
        #expect(await engine.readCaffeineChanges() == .applied(HealthCaffeineImport.Result()))
        #expect(harness.state.doses.isEmpty)
        let read = try #require(harness.state.healthLedger.lastCaffeineRead)
        #expect(read.added == 0 && read.failure == nil)
        // Still only "requested": an empty answer proves nothing about access.
        #expect(HealthChoice.readCaffeine.requestedNote.contains("no records or no read access"))
    }

    @Test func firstReadImportsThenIncrementalReadsAddAndDelete() async throws {
        let health = FakeHealth()
        health.add("A", at: base - 3 * hourMs, mg: 80)
        health.add("B", source: "com.example.watch", at: base - 2 * hourMs, mg: 40)
        let harness = Harness(reading)
        let engine = harness.engine(health)
        guard case .applied(let first) = await engine.readCaffeineChanges() else { Issue.record("not applied"); return }
        #expect(first.upserted == 2)
        #expect(Set(harness.state.doses.map(\.id)) == ["healthkit:caffeine:a", "healthkit:caffeine:b"])
        #expect(harness.state.doses.allSatisfy { !CaffeineLog.isEditable($0) && CaffeineLog.sourceLabel($0) == "Health" })
        let firstAnchor = try #require(harness.state.healthLedger.anchor(for: .caffeine))

        health.add("C", at: base - hourMs, mg: 60)
        health.delete("A")
        guard case .applied(let second) = await engine.readCaffeineChanges() else { Issue.record("not applied"); return }
        #expect(second.upserted == 1 && second.removed == 1)
        #expect(Set(harness.state.doses.map(\.id)) == ["healthkit:caffeine:b", "healthkit:caffeine:c"])
        #expect(harness.state.healthLedger.anchor(for: .caffeine)?.data != firstAnchor.data)
        #expect(harness.state.doses.first { $0.id == "healthkit:caffeine:b" }?.health?.sourceBundleIdentifier == "com.example.watch")
    }

    @Test func sameTimeAndAmountFromDifferentSourcesStayTwoRecords() async {
        let health = FakeHealth()
        health.add("A", source: "com.example.tracker", at: base - hourMs, mg: 95)
        health.add("B", source: "com.example.cafe", at: base - hourMs, mg: 95)
        health.add("C", source: "com.example.cafe", at: base - hourMs, mg: 95)
        let harness = Harness(reading)
        _ = await harness.engine(health).readCaffeineChanges()
        #expect(harness.state.doses.count == 3)
    }

    @Test func aFailedReadOrSaveLeavesTheAnchorAndRepeatsWithoutDuplicates() async throws {
        let health = FakeHealth()
        health.add("A", at: base - hourMs, mg: 80)
        let harness = Harness(reading)
        let engine = harness.engine(health)
        health.fail("read", with: FakeFailure(text: "Health is locked."))
        #expect(await engine.readCaffeineChanges() == .failed("Health is locked."))
        #expect(harness.state.healthLedger.anchor(for: .caffeine) == nil)
        #expect(harness.state.healthLedger.lastCaffeineRead?.failure == "Health is locked.")

        harness.failCommits = true
        #expect(await engine.readCaffeineChanges() == .notSaved)
        #expect(harness.state.healthLedger.anchor(for: .caffeine) == nil && harness.state.doses.isEmpty)

        harness.failCommits = false
        _ = await engine.readCaffeineChanges()
        _ = await engine.readCaffeineChanges()
        #expect(harness.state.doses.map(\.id) == ["healthkit:caffeine:a"])
    }

    @Test func turningReadingOffDiscardsTheReadInFlight() async {
        let health = FakeHealth()
        health.add("A", at: base - hourMs, mg: 80)
        let harness = Harness(reading)
        let engine = harness.engine(health)
        let gate = health.hold("read")
        async let result = engine.readCaffeineChanges()
        await gate.arrival()
        #expect(await engine.setChoice(.readCaffeine, enabled: false) == .turnedOff)
        gate.open()
        #expect(await result == .discarded)
        #expect(harness.state.doses.isEmpty && harness.state.healthLedger.anchor(for: .caffeine) == nil)
    }
}

// MARK: Exports

@MainActor
@Suite struct HealthExportTests {
    @Test func localSaveComesFirstAndHealthReportsSeparately() async throws {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        #expect(harness.saveDose("d1", mg: 95, at: base - hourMs))
        // Saved and queued together before Health is asked.
        #expect(harness.saved.doses.map(\.id) == ["d1"])
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .pending(.saveCaffeine))
        #expect(health.calls.isEmpty)

        await engine.runPendingActions(for: ["d1"])
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .exported)
        let export = try #require(harness.state.healthLedger.ownExport(forDoseID: "d1"))
        #expect(export.syncIdentifier == HealthOrigin.syncIdentifier(forDoseID: "d1") && export.syncVersion == 1)
        #expect(export.sampleUUID == health.ownStored.first?.provenance.sampleUUID)
        #expect(harness.state.healthLedger.outcomes.map(\.result) == [.succeeded])
    }

    @Test func nothingIsQueuedWhileExportIsOff() {
        let harness = Harness()
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        #expect(harness.state.healthLedger.pendingActions.isEmpty)
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .notExported)
        #expect(HealthExportStatus.notExported.value == nil)
    }

    @Test func aRefusedExportKeepsTheDoseAndRetryUsesTheSameIdentity() async throws {
        let health = FakeHealth()
        health.fail("save", with: FakeFailure(text: "Aurora can’t write caffeine to Health."))
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await engine.runPendingActions(for: ["d1"])
        #expect(harness.state.doses.map(\.id) == ["d1"])
        let failed = HealthExportStatus.of(doseID: "d1", state: harness.state)
        #expect(failed == .failed(.saveCaffeine, "Aurora can’t write caffeine to Health."))
        #expect(failed.needsAttention && failed.detail.hasPrefix("Saved on this device, not in Apple Health yet."))
        let pending = try #require(harness.state.healthLedger.pendingAction(forDoseID: "d1"))
        #expect(pending.attempts == 1 && pending.startedAt != nil)
        #expect(health.ownStored.isEmpty)

        await engine.runPendingActions()
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .exported)
        #expect(health.ownStored.count == 1)
        #expect(health.ownStored.first?.provenance.syncIdentifier == pending.syncIdentifier)
        #expect(health.ownStored.first?.provenance.syncVersion == pending.syncVersion)
    }

    @Test func anInterruptedWriteIsReconciledAfterRelaunchWithoutASecondSample() async throws {
        let health = FakeHealth()
        health.landThenFailNextSave()
        let harness = Harness(exporting)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await harness.engine(health).runPendingActions(for: ["d1"])
        // Health stored it but the answer was lost.
        #expect(health.ownStored.count == 1)
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state).needsAttention)

        // Relaunch from what was saved, then Retry.
        let relaunched = Harness { $0 = harness.saved }
        await relaunched.engine(health).runPendingActions()
        #expect(health.ownStored.count == 1)
        #expect(health.calls.filter { $0 == "save" }.count == 1)
        #expect(relaunched.state.healthLedger.ownExport(forDoseID: "d1")?.sampleUUID == health.ownStored.first?.provenance.sampleUUID)
        #expect(HealthExportStatus.of(doseID: "d1", state: relaunched.state) == .exported)
    }

    @Test func aWriteKilledMidFlightIsCheckedBeforeWritingAgain() async throws {
        let health = FakeHealth()
        let harness = Harness(exporting)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        let engine = harness.engine(health)
        let gate = health.hold("save")
        let run = Task { await engine.runPendingActions(for: ["d1"]) }
        await gate.arrival()
        // The process dies here: only what was saved survives.
        let snapshot = harness.saved
        #expect(snapshot.healthLedger.pendingAction(forDoseID: "d1")?.startedAt != nil)
        engine.invalidateAll()
        gate.open()
        await run.value
        #expect(health.ownStored.count == 1)

        let relaunched = Harness { $0 = snapshot }
        await relaunched.engine(health).runPendingActions()
        #expect(health.calls.filter { $0 == "save" }.count == 1)
        #expect(health.calls.contains("lookup"))
        #expect(HealthExportStatus.of(doseID: "d1", state: relaunched.state) == .exported)
    }

    @Test func aCorrectionReplacesOnlyAurorasSample() async throws {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        health.add("other", at: base - hourMs, mg: 95)
        await engine.runPendingActions()
        #expect(harness.correctDose("d1", mg: 120))
        #expect(harness.state.healthLedger.pendingAction(forDoseID: "d1")?.syncVersion == 2)
        await engine.runPendingActions(for: ["d1"])
        #expect(health.ownStored.map(\.mg) == [120])
        #expect(health.ownStored.first?.provenance.syncVersion == 2)
        #expect(health.stored.contains { $0.provenance.sampleUUID == "other" && $0.mg == 95 })
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .exported)
    }

    @Test func aCorrectionNeverExportsAnEntryForTheFirstTime() {
        let harness = Harness()
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        harness.state.healthChoices.writeCaffeine = true
        harness.correctDose("d1", mg: 120)
        #expect(harness.state.healthLedger.pendingActions.isEmpty)
    }

    @Test func undoRemovesOnlyAurorasSample() async throws {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        health.add("other", at: base - hourMs, mg: 95)
        await engine.runPendingActions()
        #expect(harness.removeDose("d1"))
        #expect(harness.state.doses.isEmpty)
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .pending(.deleteCaffeine))
        await engine.runPendingActions(for: ["d1"])
        #expect(health.ownStored.isEmpty)
        #expect(health.stored.map(\.provenance.sampleUUID) == ["other"])
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .removed)
    }

    @Test func aFailedRemovalIsReportedApartFromTheLocalRemoval() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await engine.runPendingActions()
        health.fail("delete", with: FakeFailure(text: "Health is locked."))
        harness.removeDose("d1")
        await engine.runPendingActions(for: ["d1"])
        #expect(harness.state.doses.isEmpty)
        let status = HealthExportStatus.of(doseID: "d1", state: harness.state)
        #expect(status == .failed(.deleteCaffeine, "Health is locked."))
        #expect(status.detail.hasPrefix("Removed on this device."))
        await engine.runPendingActions()
        #expect(health.ownStored.isEmpty)
    }

    @Test func undoBeforeTheExportStartsNeverReachesHealth() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        harness.removeDose("d1")
        #expect(harness.state.healthLedger.pendingActions.isEmpty)
        await harness.engine(health).runPendingActions()
        #expect(health.calls.isEmpty)
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .notExported)
    }

    @Test func undoWhileTheExportIsInFlightLeavesNoAuroraSample() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        let gate = health.hold("save")
        let run = Task { await engine.runPendingActions(for: ["d1"]) }
        await gate.arrival()
        harness.removeDose("d1")
        #expect(harness.state.healthLedger.pendingAction(forDoseID: "d1")?.kind == .deleteCaffeine)
        // A second request waits for the save instead of racing it.
        let removal = Task { await engine.runPendingActions(for: ["d1"]) }
        gate.open()
        await run.value
        await removal.value
        #expect(health.ownStored.isEmpty)
        #expect(health.calls.filter { $0 == "save" || $0 == "delete" } == ["save", "delete"])
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .removed)
        // The cancelled save is never reported as succeeded.
        #expect(!harness.state.healthLedger.outcomes.contains { $0.kind == .saveCaffeine && $0.result == .succeeded })
    }

    @Test func revokedWriteAccessKeepsEntriesLocalAndPending() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await engine.runPendingActions()
        health.fail("save", with: FakeFailure(text: "Aurora can’t write caffeine to Health."))
        harness.saveDose("d2", mg: 60, at: base - 30 * minuteMs)
        await engine.runPendingActions(for: ["d2"])
        #expect(harness.state.doses.map(\.id) == ["d1", "d2"])
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .exported)
        #expect(HealthExportStatus.of(doseID: "d2", state: harness.state).needsAttention)
    }

    @Test func turningExportOffCancelsTheQueueAndKeepsHealthCopies() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await engine.runPendingActions()
        harness.saveDose("d2", mg: 60, at: base - 30 * minuteMs)
        #expect(await engine.setChoice(.writeCaffeine, enabled: false) == .turnedOff)
        #expect(harness.state.healthLedger.pendingActions.isEmpty)
        #expect(HealthExportStatus.of(doseID: "d2", state: harness.state) == .cancelled)
        await engine.runPendingActions()
        #expect(health.ownStored.count == 1)
        // Edits and removals while off leave Health as it was, and say so.
        harness.correctDose("d1", mg: 120)
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .outdated)
        harness.removeDose("d1")
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .keptInHealth)
        #expect(health.ownStored.map(\.mg) == [95])
    }

    @Test func turningExportOffMidWriteNeverClaimsTheOutcome() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        let gate = health.hold("save")
        let run = Task { await engine.runPendingActions(for: ["d1"]) }
        await gate.arrival()
        #expect(await engine.setChoice(.writeCaffeine, enabled: false) == .turnedOff)
        gate.open()
        await run.value
        // The late write landed, but its answer is stale and isn't recorded.
        #expect(health.ownStored.count == 1)
        #expect(harness.state.healthLedger.ownExports.isEmpty && harness.state.healthLedger.pendingActions.isEmpty)
        #expect(!harness.state.healthLedger.outcomes.contains { $0.result == .succeeded })
        #expect(HealthExportStatus.of(doseID: "d1", state: harness.state) == .uncertain)
        // Reading it back still recognises it as Aurora's, with its dose.
        harness.state.healthChoices = HealthChoices(readCaffeine: true)
        guard case .applied(let result) = await engine.readCaffeineChanges() else { Issue.record("not applied"); return }
        #expect(result.skippedOwn == 1 && harness.state.doses.map(\.id) == ["d1"])
    }

    @Test func ownExportsReadBackAreNotImportedTwice() async {
        let health = FakeHealth()
        let harness = Harness { $0.healthChoices = HealthChoices(readCaffeine: true, writeCaffeine: true) }
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await engine.runPendingActions()
        guard case .applied(let result) = await engine.readCaffeineChanges() else { Issue.record("not applied"); return }
        #expect(result.skippedOwn == 1 && result.upserted == 0)
        #expect(harness.state.doses.map(\.id) == ["d1"])
    }
}

// MARK: Erase, observers and refresh

@MainActor
@Suite struct HealthEraseAndRefreshTests {
    @Test func eraseDuringAnImportDiscardsItAndStopsObservers() async {
        let health = FakeHealth()
        health.add("A", at: base - hourMs, mg: 80)
        let harness = Harness(reading)
        let engine = harness.engine(health)
        await engine.startObservers()
        #expect(health.activeObservers == [.caffeine])
        let gate = health.hold("read")
        async let result = engine.readCaffeineChanges()
        await gate.arrival()
        harness.erase(engine)
        #expect(health.activeObservers.isEmpty)
        gate.open()
        #expect(await result == .discarded)
        #expect(harness.state == AppState() && harness.saved == AppState())
    }

    @Test func eraseDuringAnExportDropsTheOutboxAndLeavesHealthAlone() async {
        let health = FakeHealth()
        let harness = Harness(exporting)
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        harness.saveDose("d2", mg: 60, at: base - 30 * minuteMs)
        let gate = health.hold("save")
        let run = Task { await engine.runPendingActions() }
        await gate.arrival()
        harness.erase(engine)
        gate.open()
        await run.value
        #expect(harness.saved == AppState())
        // The write that was already in flight stays in Health; the queued one never started.
        #expect(health.ownStored.count == 1)
        #expect(health.calls.filter { $0 == "save" }.count == 1)
    }

    @Test func afterEraseAndRelaunchNothingRestartsUntilChosenAgain() async {
        let health = FakeHealth()
        let harness = Harness(reading)
        let engine = harness.engine(health)
        await engine.startObservers()
        harness.erase(engine)
        let relaunched = Harness { $0 = harness.saved }
        let fresh = relaunched.engine(health)
        await fresh.startObservers()
        #expect(health.activeObservers.isEmpty)
        #expect(await fresh.readCaffeineChanges() == .skipped)
        await fresh.runPendingActions()
        #expect(relaunched.state.healthLedger == .empty)
        #expect(!health.calls.contains("read"))
    }

    @Test func aurorasExportsAfterEraseComeBackReadOnly() async {
        let health = FakeHealth()
        let harness = Harness { $0.healthChoices = HealthChoices(readCaffeine: true, writeCaffeine: true) }
        let engine = harness.engine(health)
        harness.saveDose("d1", mg: 95, at: base - hourMs)
        await engine.runPendingActions()
        harness.erase(engine)
        harness.state.healthChoices = HealthChoices(readCaffeine: true)
        guard case .applied(let result) = await harness.engine(health).readCaffeineChanges() else { Issue.record("not applied"); return }
        #expect(result.keptOwnWithoutLocalDose == 1)
        #expect(harness.state.doses.allSatisfy { RecordID.isHealthCaffeine($0.id) && !CaffeineLog.isEditable($0) })
    }

    @Test func observerNotificationsAlwaysComplete() async {
        let health = FakeHealth()
        let harness = Harness { $0.healthChoices = HealthChoices(readSleep: true, readCaffeine: true) }
        let engine = harness.engine(health)
        var seen: [HealthDataKind] = []
        engine.onChange = { seen.append($0) }
        await engine.startObservers()
        #expect(health.activeObservers == [.sleepAnalysis, .caffeine])
        await health.fire(.caffeine)
        await health.fire(.sleepAnalysis)
        #expect(seen == [.caffeine, .sleepAnalysis])
        #expect(health.completions == 2)
        // Starting again doesn't register twice.
        await engine.startObservers()
        await health.fire(.caffeine)
        #expect(health.completions == 3)
        #expect(await engine.setChoice(.readCaffeine, enabled: false) == .turnedOff)
        #expect(health.activeObservers == [.sleepAnalysis])
    }

    @Test func aBurstOfNotificationsCoalescesIntoOneFollowUp() async {
        var batches: [Set<RefreshTrigger>] = []
        let gate = Gate()
        let scheduler = RefreshScheduler { triggers, _ in
            batches.append(triggers)
            if batches.count == 1 { await gate.pass() }
        }
        let first = Task { await scheduler.request(.foreground) }
        await gate.arrival()
        let burst = (0..<5).map { index in
            Task { await scheduler.request(index.isMultiple(of: 2) ? .healthChange(.caffeine) : .healthChange(.sleepAnalysis)) }
        }
        await Task.yield()
        gate.open()
        await first.value
        for task in burst { await task.value }
        #expect(scheduler.runCount == 2)
        #expect(batches == [[.foreground], [.healthChange(.caffeine), .healthChange(.sleepAnalysis)]])
        #expect(!scheduler.isRunning)
    }

    @Test func invalidationReleasesWaitersAndMarksWorkStale() async {
        let gate = Gate()
        var stale: Bool?
        var scheduler: RefreshScheduler!
        scheduler = RefreshScheduler { _, isCurrent in
            await gate.pass()
            stale = !isCurrent()
        }
        let waiting = Task { await scheduler.request(.background) }
        await gate.arrival()
        scheduler.invalidate()
        await waiting.value
        gate.open()
        for _ in 0..<20 where stale == nil { await Task.yield() }
        #expect(stale == true)
        await scheduler.request(.explicit)
        #expect(scheduler.runCount == 2)
    }

    @Test func policyRefreshesOnlyWhatEachTriggerNeeds() {
        let now = base
        let fresh: [RefreshPolicy.Step: Millis] = [.healthSleep: now - minuteMs, .healthCaffeine: now - minuteMs, .calendars: now - minuteMs]
        #expect(RefreshPolicy.steps(for: [.healthChange(.caffeine)], lastRun: fresh, now: now) == [.healthCaffeine])
        #expect(RefreshPolicy.steps(for: [.healthChange(.sleepAnalysis)], lastRun: [:], now: now) == [.healthSleep])
        #expect(RefreshPolicy.steps(for: [.foreground], lastRun: fresh, now: now) == [.suggestions])
        #expect(RefreshPolicy.steps(for: [.background], lastRun: [:], now: now) == RefreshPolicy.Step.allCases)
        #expect(RefreshPolicy.steps(for: [.explicit], lastRun: fresh, now: now) == [.healthSleep, .healthCaffeine, .calendars])
        let stale = fresh.mapValues { $0 - RefreshPolicy.minimumInterval }
        #expect(RefreshPolicy.steps(for: [.foreground], lastRun: stale, now: now) == RefreshPolicy.Step.allCases)
        // A clock set backwards doesn't freeze refresh.
        #expect(RefreshPolicy.steps(for: [.foreground], lastRun: [.calendars: now + hourMs], now: now).contains(.calendars))
    }
}

// MARK: Labels

@Suite struct HealthLabelTests {
    private let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)

    @Test func healthCaffeineIsNamedAsHealthWherePresentedAndExported() {
        #expect(RecordSource.of(ids: ["d1"]) == .manual)
        #expect(RecordSource.of(ids: ["healthkit:caffeine:a"]) == .health)
        #expect(RecordSource.of(ids: ["d1", "healthkit:caffeine:a"]) == .manualAndHealth)
        #expect(RecordSource.of(ids: ["demo:1", "healthkit:caffeine:a"]) == .healthAndSample)
        #expect(RecordSource.of(ids: ["demo:1", "d1", "healthkit:caffeine:a"]) == .allSources)
        #expect(RecordSource.of(ids: ["demo:1", "d1"]) == .mixed && RecordSource.mixed.includesSample)
        #expect(!RecordSource.manualAndHealth.includesSample)

        let health = Dose(id: "healthkit:caffeine:a", timestamp: base - hourMs, mg: 80,
                          health: HealthSampleProvenance(sampleUUID: "a", sourceBundleIdentifier: "com.example.tracker"))
        let today = CaffeineLog.loggedToday([health], now: base, clock: utc, formatTime: { _ in "9:41" })
        #expect(today.source == "Health" && !today.sample)
        let rows = Export.dailyTotalRows([health], now: base, clock: utc)
        #expect(rows.last?.source == "Health")
    }

    @Test func aurorasEarlierCopiesAreLabeledAndReadOnly() {
        let own = Dose(id: "healthkit:caffeine:x", timestamp: base - hourMs, mg: 95,
                       health: HealthSampleProvenance(sampleUUID: "x", sourceBundleIdentifier: HealthOrigin.appBundleIdentifier))
        let other = Dose(id: "healthkit:caffeine:y", timestamp: base - hourMs, mg: 95,
                         health: HealthSampleProvenance(sampleUUID: "y", sourceBundleIdentifier: "com.example.tracker"))
        #expect(CaffeineLog.isEarlierAuroraCopy(own) && !CaffeineLog.isEditable(own))
        #expect(!CaffeineLog.isEarlierAuroraCopy(other))
        #expect(CaffeineLog.describe(own, formatDateTime: { _ in "" }).contains("Added to Health by Aurora earlier"))
    }

    @Test func outboxAndReadSummariesStayFactual() {
        var ledger = HealthSyncLedger()
        #expect(ledger.outboxSummary == nil && ledger.caffeineReadSummary == nil)
        ledger.enqueue(.saveCaffeine, doseID: "d1", now: base, id: "a1")
        ledger.enqueue(.saveCaffeine, doseID: "d2", now: base, id: "a2")
        ledger.finish(actionID: "a1", result: .failed, message: "Locked.", now: base)
        #expect(ledger.outboxSummary == "1 change not accepted by Apple Health yet · 1 waiting. Saved on this device either way.")
        ledger.lastCaffeineRead = HealthReadRecord(finishedAt: base)
        #expect(ledger.caffeineReadSummary == "Last caffeine read found no changes.")
        ledger.lastCaffeineRead = HealthReadRecord(finishedAt: base, failure: "Locked.")
        let results: [HealthSyncEngine.ChoiceResult] = [.unavailable, .unsupported, .sampleData, .paused, .notSaved]
        let texts = [ledger.outboxSummary ?? "", ledger.caffeineReadSummary ?? ""]
            + results.compactMap(\.message) + [CaffeineLog.earlierAuroraCopyNote]
        for text in texts {
            #expect(CopyRules.violations(in: text).isEmpty)
            #expect(!text.lowercased().contains("granted") && !text.lowercased().contains("denied"))
        }
    }
}
