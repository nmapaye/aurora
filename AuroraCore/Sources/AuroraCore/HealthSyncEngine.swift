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
        guard enabled else { return turnOff(choice) }
        let state = host.state()
        guard state.healthLedger.isSupported else { return .paused }
        guard !state.demoMode else { return .sampleData }
        guard provider.isAvailable else { return .unavailable }
        guard provider.capabilities.isSuperset(of: choice.requiredCapabilities) else { return .unsupported }
        let generations = (readGenerations, exportGeneration)
        do {
            try await provider.requestAuthorization(read: choice.readKinds, write: choice.writeKinds)
        } catch {
            guard generations == (readGenerations, exportGeneration) else { return .discarded }
            return .failed(Self.message(for: error))
        }
        guard generations == (readGenerations, exportGeneration) else { return .discarded }
        guard host.commit({ $0.healthChoices[choice] = true }) else { return .notSaved }
        if !choice.readKinds.isEmpty { await startObservers() }
        return .requested
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
                if wasStarted, let existing = try await provider.ownCaffeineSample(syncIdentifier: action.syncIdentifier),
                   (existing.syncVersion ?? 0) >= action.syncVersion {
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

    // MARK: Erase

    /// For Delete All Records and full erase: stops observers, makes every
    /// in-flight read and write stale, and forgets the outbox chain. Samples
    /// already in Health stay there.
    public func invalidateAll() {
        for kind in HealthDataKind.allCases { readGenerations[kind, default: 0] += 1 }
        exportGeneration += 1
        exportTail = nil
        caffeineReadGeneration = nil
        stopObservers()
    }
}
