import Foundation

extension HealthProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health isn’t available on this device."
        case .unsupported: "This Health action isn’t available."
        }
    }
}

/// Everything Aurora does with Health beyond the sleep import: separate
/// choices, anchored caffeine reads, observers, and the outbox of Aurora's
/// own caffeine writes and deletes.
///
/// Local records always come first. Saving, correcting or removing a dose is
/// stored, together with any queued Health action, before Health is asked
/// anything; Health's answer is recorded as a separate outcome. Each action
/// is marked started before Health is called, so after an interruption the
/// retry looks for Aurora's sample before writing it again.
///
/// Generations make late results harmless. Turning a choice off, Delete
/// All Records and full erase bump them, so a read or write that lands
/// afterwards is never applied.
@MainActor
public final class HealthSyncEngine {
    /// The app's state, reached without the engine owning it.
    public struct Host {
        public var state: @MainActor () -> AppState
        /// Applies and saves a change. False means it couldn't be saved and
        /// nothing changed.
        public var commit: @MainActor (_ change: (inout AppState) -> Void) -> Bool
        public var now: @MainActor () -> Millis
        public var newActionID: @MainActor () -> String

        public init(
            state: @escaping @MainActor () -> AppState,
            commit: @escaping @MainActor (_ change: (inout AppState) -> Void) -> Bool,
            now: @escaping @MainActor () -> Millis,
            newActionID: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() }
        ) {
            self.state = state
            self.commit = commit
            self.now = now
            self.newActionID = newActionID
        }
    }

    public enum ChoiceResult: Equatable, Sendable {
        /// Health's sheet finished. This says nothing about what was allowed.
        case requested
        case turnedOff
        case unavailable
        case unsupported
        /// Sample Data is on, so Health stays untouched.
        case sampleData
        /// The ledger is from a newer build; Health sync is paused.
        case paused
        case failed(String)
        case notSaved
        /// Erased or turned off while Health's sheet was open.
        case discarded
    }

    public enum ReadResult: Equatable, Sendable {
        case skipped
        case applied(HealthCaffeineImport.Result)
        case appliedSleep(HealthSleepImport.Result)
        case failed(String)
        case discarded
        case notSaved
    }

    public let provider: any HealthDataProvider
    private let host: Host
    private var readGenerations: [HealthDataKind: Int] = [:]
    public private(set) var exportGeneration = 0
    private var observations: [HealthDataKind: HealthObservation] = [:]
    private var exportTail: Task<Void, Never>?
    private var caffeineReadGeneration: Int?
    private var sleepReadGeneration: Int?
    private var reconciledThisLaunch = false

    /// Runs when Health reports a change to an observed kind. Health is told
    /// the notification was handled only after this returns.
    public var onChange: (@MainActor (HealthDataKind) async -> Void)?

    public init(provider: any HealthDataProvider, host: Host) {
        self.provider = provider
        self.host = host
    }

    public func readGeneration(_ kind: HealthDataKind) -> Int { readGenerations[kind, default: 0] }
    public var observedKinds: Set<HealthDataKind> { Set(observations.keys) }

    public static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Apple Health didn’t complete the request."
    }

    // MARK: Choices

    /// Turning a choice on asks Health for that one permission and stores
    /// the choice only after the sheet finishes. Turning it off stops its
    /// observer and makes in-flight work stale; turning export off also
    /// cancels queued actions. Nothing already in Health is removed.
    public func setChoice(_ choice: HealthChoice, enabled: Bool) async -> ChoiceResult {
        guard enabled else {
            let result = turnOff(choice)
            await reconcileBackgroundDelivery()
            return result
        }
        let state = host.state()
        guard state.healthLedger.isSupported else { return .paused }
        guard !state.demoMode else { return .sampleData }
        guard provider.isAvailable else { return .unavailable }
        guard provider.capabilities.isSuperset(of: choice.requiredCapabilities) else { return .unsupported }
        if choice == .backgroundUpdates { return await turnOnBackgroundUpdates() }
        let generations = (readGenerations, exportGeneration)
        do {
            try await provider.requestAuthorization(read: choice.readKinds, write: choice.writeKinds)
        } catch {
            guard generations == (readGenerations, exportGeneration) else { return .discarded }
            return .failed(Self.message(for: error))
        }
        guard generations == (readGenerations, exportGeneration) else { return .discarded }
        guard host.commit({ $0.healthChoices[choice] = true }) else { return .notSaved }
        if !choice.readKinds.isEmpty {
            await startObservers()
            await reconcileBackgroundDelivery()
        }
        return .requested
    }

    /// Asks Health to wake Aurora for the kinds it reads, and stores the
    /// choice only if Health accepted. Asks for no Health permission.
    private func turnOnBackgroundUpdates() async -> ChoiceResult {
        let kinds = host.state().healthChoices.observedKinds
        let generations = readGenerations
        do {
            if !kinds.isEmpty { try await provider.setBackgroundDelivery(kinds, enabled: true) }
        } catch {
            guard generations == readGenerations else { return .discarded }
            return .failed(Self.message(for: error))
        }
        guard generations == readGenerations else {
            await reconcileBackgroundDelivery()
            return .discarded
        }
        guard host.commit({ $0.healthChoices.backgroundUpdates = true }) else {
            await reconcileBackgroundDelivery()
            return .notSaved
        }
        await startObservers()
        return .requested
    }

    /// Makes Health's wake-ups match the stored choices: on for kinds read
    /// while opted in, off for every other kind. Health keeps this setting
    /// across launches, so it runs at launch and after any change, and
    /// re-checks once if choices changed while Health was answering.
    public func reconcileBackgroundDelivery() async {
        guard provider.capabilities.contains(.backgroundDelivery) else { return }
        for _ in 0..<2 {
            let state = host.state()
            let wanted = state.healthLedger.isSupported && !state.demoMode ? state.healthChoices.backgroundKinds : []
            let unwanted = Set(HealthDataKind.allCases).subtracting(wanted)
            try? await provider.setBackgroundDelivery(unwanted, enabled: false)
            if !wanted.isEmpty { try? await provider.setBackgroundDelivery(wanted, enabled: true) }
            let now = host.state()
            let still = now.healthLedger.isSupported && !now.demoMode ? now.healthChoices.backgroundKinds : []
            if still == wanted { return }
        }
    }

    private func turnOff(_ choice: HealthChoice) -> ChoiceResult {
        for kind in choice.readKinds { readGenerations[kind, default: 0] += 1 }
        if choice == .writeCaffeine {
            exportGeneration += 1
            exportTail = nil
        }
        stopObservers(choice.readKinds)
        let now = host.now()
        let saved = host.commit {
            $0.healthChoices[choice] = false
            if choice == .writeCaffeine { $0.healthLedger.cancelPending(now: now) }
        }
        return saved ? .turnedOff : .notSaved
    }

    // MARK: Observers

    /// Starts an observer for each kind Aurora reads and isn't watching yet.
    public func startObservers() async {
        if !reconciledThisLaunch {
            reconciledThisLaunch = true
            await reconcileBackgroundDelivery()
        }
        let state = host.state()
        guard state.healthLedger.isSupported, !state.demoMode, provider.capabilities.contains(.observeChanges) else { return }
        let wanted = state.healthChoices.observedKinds.subtracting(observations.keys)
        for kind in HealthDataKind.allCases where wanted.contains(kind) {
            let generation = readGeneration(kind)
            guard let observation = try? await provider.startObserving([kind], onChange: { [weak self] kind in
                await self?.observed(kind)
            }) else { continue }
            // Turned off, erased or started twice while registering.
            let current = host.state()
            guard generation == readGeneration(kind), current.healthChoices.observedKinds.contains(kind),
                  !current.demoMode, observations[kind] == nil else {
                provider.stopObserving(observation)
                continue
            }
            observations[kind] = observation
        }
    }

    /// Stops observers for `kinds`, or all of them.
    public func stopObservers(_ kinds: Set<HealthDataKind>? = nil) {
        for (kind, observation) in observations where kinds?.contains(kind) ?? true {
            provider.stopObserving(observation)
            observations[kind] = nil
        }
    }

    private func observed(_ kind: HealthDataKind) async {
        guard observations[kind] != nil, let onChange else { return }
        await onChange(kind)
    }

    // MARK: Reading caffeine

    /// One anchored read. Additions and deletions apply by sample UUID only,
    /// and the new anchor is saved with them, so a failed read or save
    /// leaves the anchor where it was and the next read repeats safely.
    public func readCaffeineChanges() async -> ReadResult {
        let state = host.state()
        let generation = readGeneration(.caffeine)
        guard state.healthChoices.readCaffeine, !state.demoMode, state.healthLedger.isSupported,
              provider.capabilities.contains(.readCaffeineChanges), caffeineReadGeneration != generation else { return .skipped }
        caffeineReadGeneration = generation
        defer { if caffeineReadGeneration == generation { caffeineReadGeneration = nil } }
        let anchor = state.healthLedger.anchor(for: .caffeine)?.data
        let changes: HealthCaffeineChanges
        do {
            changes = try await provider.caffeineChanges(after: anchor)
        } catch {
            guard isCurrentRead(generation, anchor: anchor) else { return .discarded }
            let message = Self.message(for: error)
            let now = host.now()
            _ = host.commit { $0.healthLedger.lastCaffeineRead = HealthReadRecord(finishedAt: now, failure: message) }
            return .failed(message)
        }
        guard isCurrentRead(generation, anchor: anchor) else { return .discarded }
        let now = host.now()
        var result = HealthCaffeineImport.Result()
        let saved = host.commit {
            result = $0.applyHealthCaffeine(changes, now: now)
            $0.healthLedger.lastCaffeineRead = HealthReadRecord(finishedAt: now, added: result.upserted, removed: result.removed)
        }
        return saved ? .applied(result) : .notSaved
    }

    // MARK: Reading sleep

    /// One anchored sleep read, keyed by sample UUID with provenance. The
    /// anchor moves only with the records it produced. The caller records
    /// the sleep status; failures leave records and anchor unchanged.
    public func readSleepChanges() async -> ReadResult {
        let state = host.state()
        let generation = readGeneration(.sleepAnalysis)
        guard state.healthChoices.readSleep, !state.demoMode, state.healthLedger.isSupported,
              provider.capabilities.contains(.readSleepChanges), sleepReadGeneration != generation else { return .skipped }
        sleepReadGeneration = generation
        defer { if sleepReadGeneration == generation { sleepReadGeneration = nil } }
        let anchor = state.healthLedger.anchor(for: .sleepAnalysis)?.data
        let changes: HealthSleepChanges
        do {
            changes = try await provider.sleepChanges(after: anchor)
        } catch {
            guard isCurrentSleepRead(generation, anchor: anchor) else { return .discarded }
            return .failed(Self.message(for: error))
        }
        guard isCurrentSleepRead(generation, anchor: anchor) else { return .discarded }
        let now = host.now()
        var result = HealthSleepImport.Result()
        let saved = host.commit {
            result = $0.applyHealthSleep(changes, now: now)
            HealthImport.recordAnchoredRead(now: now, to: &$0)
        }
        return saved ? .appliedSleep(result) : .notSaved
    }

    private func isCurrentSleepRead(_ generation: Int, anchor: Data?) -> Bool {
        let state = host.state()
        return generation == readGeneration(.sleepAnalysis) && state.healthChoices.readSleep && !state.demoMode
            && state.healthLedger.anchor(for: .sleepAnalysis)?.data == anchor
    }

    private func isCurrentRead(_ generation: Int, anchor: Data?) -> Bool {
        let state = host.state()
        return generation == readGeneration(.caffeine) && state.healthChoices.readCaffeine && !state.demoMode
            && state.healthLedger.anchor(for: .caffeine)?.data == anchor
    }

    // MARK: Writing Aurora's caffeine

    /// Runs queued actions one at a time, oldest first. Calls are chained, so
    /// a save and a later delete for the same entry never overlap. `doseIDs`
    /// limits the run; nil runs everything, as Retry does.
    public func runPendingActions(for doseIDs: Set<String>? = nil) async {
        let previous = exportTail
        let generation = exportGeneration
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.drain(doseIDs, generation: generation)
        }
        exportTail = task
        await task.value
    }

    private func drain(_ doseIDs: Set<String>?, generation: Int) async {
        var handled: Set<String> = []
        while generation == exportGeneration {
            let state = host.state()
            guard state.healthExportActive,
                  let action = state.healthLedger.pendingActions.first(where: {
                      !handled.contains($0.id) && (doseIDs?.contains($0.doseID) ?? true)
                  }) else { return }
            handled.insert(action.id)
            await attempt(action, generation: generation)
        }
    }

    private func attempt(_ action: HealthPendingAction, generation: Int) async {
        let needed: HealthCapabilities = action.kind == .saveCaffeine ? .writeOwnCaffeine : .deleteOwnCaffeine
        let dose = host.state().doses.first { $0.id == action.doseID }
        // A save whose dose is gone was replaced by its removal, if any.
        if action.kind == .saveCaffeine && dose == nil { return }
        let wasStarted = action.startedAt != nil
        let started = host.now()
        guard host.commit({ $0.healthLedger.markStarted(actionID: action.id, at: started) }) else { return }
        var sampleUUID: String?
        var failure: String?
        do {
            guard provider.capabilities.contains(needed) else { throw HealthProviderError.unsupported(action.kind.rawValue) }
            switch action.kind {
            case .saveCaffeine:
                guard let dose else { return }
                var existing: HealthSampleProvenance?
                if wasStarted {
                    existing = try await provider.ownCaffeineSample(syncIdentifier: action.syncIdentifier)
                    // The lookup suspended. Before any new write, the action must
                    // still be this exact one, for this dose as it was, with
                    // export on and nothing erased or turned off meanwhile.
                    guard stillCurrent(action, dose: dose, generation: generation) else { return }
                }
                if let existing, (existing.syncVersion ?? 0) >= action.syncVersion {
                    // The interrupted write landed; adopt it instead of writing again.
                    sampleUUID = existing.sampleUUID
                } else {
                    sampleUUID = try await provider.saveOwnCaffeine(HealthCaffeineWrite(
                        doseID: dose.id, timestamp: dose.timestamp, mg: dose.mg,
                        syncIdentifier: action.syncIdentifier, syncVersion: action.syncVersion
                    ))
                }
            case .deleteCaffeine:
                try await provider.deleteOwnCaffeine(syncIdentifier: action.syncIdentifier)
            }
        } catch {
            failure = Self.message(for: error)
        }
        // Erased or export turned off meanwhile: the answer is stale.
        guard generation == exportGeneration else { return }
        let now = host.now()
        _ = host.commit {
            $0.healthLedger.finish(
                actionID: action.id, result: failure == nil ? .succeeded : .failed,
                sampleUUID: sampleUUID, exported: dose, message: failure, now: now
            )
        }
    }

    /// True while `action` is still the queued action for its dose, unchanged,
    /// the dose is recorded as it was, export is active, and no invalidation
    /// happened. Checked after every suspension before starting another
    /// external operation.
    private func stillCurrent(_ action: HealthPendingAction, dose: Dose?, generation: Int) -> Bool {
        let state = host.state()
        guard generation == exportGeneration, state.healthExportActive,
              let queued = state.healthLedger.pendingAction(forDoseID: action.doseID),
              queued.id == action.id, queued.kind == action.kind, queued.syncVersion == action.syncVersion,
              queued.syncIdentifier == action.syncIdentifier else { return false }
        guard let dose else { return true }
        return state.doses.first { $0.id == dose.id } == dose
    }

    // MARK: Erase

    /// For Delete All Records and full erase: stops observers, makes every
    /// in-flight read and write stale, and forgets the outbox chain. Samples
    /// already in Health stay there.
    public func invalidateAll() {
        for kind in HealthDataKind.allCases { readGenerations[kind, default: 0] += 1 }
        exportGeneration += 1
        exportTail = nil
        caffeineReadGeneration = nil
        sleepReadGeneration = nil
        stopObservers()
        // Health keeps wake-ups across launches; match them to the choices
        // that remain (none after full erase).
        Task { await reconcileBackgroundDelivery() }
    }
}
