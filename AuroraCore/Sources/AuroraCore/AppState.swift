import Foundation

/// Everything Aurora stores. The app keeps one value of this and saves it
/// whole; every change goes through the mutating functions below, which
/// match the React Native store's actions.
public struct AppState: Codable, Equatable, Sendable {
    /// 2 added energy check-ins and the Health sync ledger. A version-1 file
    /// is migrated by `StateMigration`, which keeps the original beside it.
    public static let schemaVersion = 2
    /// Health-imported sleep is a cache of data that stays in Health, so it is
    /// trimmed to this many days. Manual and sample sleep is never trimmed.
    public static let healthSleepRetentionDays: Double = 180

    public var schemaVersion: Int = AppState.schemaVersion
    public var doses: [Dose] = []
    public var sleeps: [SleepSession] = []
    public var vigilanceSessions: [VigilanceSession] = []
    public var prefs: Prefs = .defaults
    public var onboarding: Onboarding = .defaults
    public var healthSync: HealthSync = .defaults
    /// The Sample Data flag.
    public var demoMode: Bool = false
    public var appearanceMode: AppearanceMode = .system
    public var energyCheckIns: [EnergyCheckIn] = []
    public var healthLedger: HealthSyncLedger = .empty
    /// What the person turned on, one choice per Health permission. A choice
    /// records the request, never what Health allowed.
    public var healthChoices: HealthChoices = .off

    public init() {}

    public static func withinHealthRetention(_ sleeps: [SleepSession], now: Millis) -> [SleepSession] {
        let oldest = now - healthSleepRetentionDays * dayMs
        return sleeps.filter { !RecordID.isHealthSleep($0.id) || $0.end >= oldest }
    }

    /// Newest end first; equal ends keep their order.
    static func sortedByEndDescending(_ sleeps: [SleepSession]) -> [SleepSession] {
        stableSorted(sleeps) { $0.end > $1.end }
    }

    static func stableSorted<T>(_ items: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func clampWalkthroughStep(_ step: Int) -> Int {
        clamp(step, 0, 9)
    }

    // MARK: Caffeine

    public mutating func addDose(_ dose: Dose) {
        doses.append(dose)
    }

    /// Replaces an entry's recorded fields. The entry keeps its id. Health
    /// caffeine belongs to Health and is never changed here.
    public mutating func updateDose(id: String, timestamp: Millis, mg: Double, source: String?, note: String?) {
        guard !RecordID.isHealthCaffeine(id), let index = doses.firstIndex(where: { $0.id == id }) else { return }
        doses[index].timestamp = timestamp
        doses[index].mg = mg
        doses[index].source = source
        doses[index].note = note
    }

    public mutating func updateDose(id: String, with patch: Dose) {
        updateDose(id: id, timestamp: patch.timestamp, mg: patch.mg, source: patch.source, note: patch.note)
    }

    /// Health caffeine leaves only when Health reports it deleted.
    public mutating func removeDose(id: String) {
        guard !RecordID.isHealthCaffeine(id) else { return }
        doses.removeAll { $0.id == id }
    }

    /// Applies an anchored Health caffeine read. Samples are matched only by
    /// their Health UUID, never by time and amount. Aurora's own exports are
    /// skipped only while their dose is still recorded here; without one they
    /// are kept read-only like any Health record. The anchor is saved with
    /// the records it produced.
    @discardableResult
    public mutating func applyHealthCaffeine(_ changes: HealthCaffeineChanges, now: Millis) -> HealthCaffeineImport.Result {
        var result = HealthCaffeineImport.Result()
        let deleted = Set(changes.deletedSampleUUIDs.map { RecordID.healthCaffeineID(sampleUUID: $0) })
        let before = doses.count
        doses.removeAll { deleted.contains($0.id) }
        result.removed = before - doses.count
        for sample in changes.added {
            guard HealthCaffeineImport.isValid(sample) else {
                result.rejected += 1
                continue
            }
            switch HealthOrigin.ownership(of: sample.provenance, ledger: healthLedger, doses: doses) {
            case .thirdParty: break
            case .ownWithLocalDose:
                result.skippedOwn += 1
                continue
            case .ownWithoutLocalDose: result.keptOwnWithoutLocalDose += 1
            }
            let dose = HealthCaffeineImport.dose(from: sample)
            if let index = doses.firstIndex(where: { $0.id == dose.id }) {
                doses[index] = dose
            } else {
                doses.append(dose)
            }
            result.upserted += 1
        }
        healthLedger.setAnchor(changes.anchor, for: .caffeine, at: now)
        return result
    }

    /// Queues a Health write for an entry Aurora recorded. Sample Data and
    /// Health caffeine are never exported. A delete needs an earlier export
    /// or a save that started and may have reached Health.
    @discardableResult
    public mutating func enqueueHealthExport(_ kind: HealthPendingAction.Kind, doseID: String, now: Millis, id: String) -> HealthPendingAction? {
        guard !RecordID.isSample(doseID), !RecordID.isHealthCaffeine(doseID) else { return nil }
        switch kind {
        case .saveCaffeine: guard doses.contains(where: { $0.id == doseID }) else { return nil }
        case .deleteCaffeine:
            let startedSave = healthLedger.pendingAction(forDoseID: doseID).map { $0.kind == .saveCaffeine && $0.startedAt != nil } ?? false
            guard healthLedger.ownExport(forDoseID: doseID) != nil || startedSave else { return nil }
        }
        return healthLedger.enqueue(kind, doseID: doseID, now: now, id: id)
    }

    /// Whether Aurora may write to Health now: the person turned export on,
    /// Sample Data is off, and the ledger is one this build understands.
    public var healthExportActive: Bool {
        healthChoices.writeCaffeine && !demoMode && healthLedger.isSupported
    }

    /// Call in the same change that saved or corrected a dose, so the local
    /// record and its queued export are stored together. Nothing is queued
    /// while export is off.
    @discardableResult
    public mutating func queueHealthSave(doseID: String, now: Millis, id: String) -> HealthPendingAction? {
        guard healthExportActive else { return nil }
        return enqueueHealthExport(.saveCaffeine, doseID: doseID, now: now, id: id)
    }

    /// Call in the same change that corrected a dose. Only a dose already
    /// exported or queued is sent again; a correction never exports an
    /// entry for the first time.
    @discardableResult
    public mutating func queueHealthCorrection(doseID: String, now: Millis, id: String) -> HealthPendingAction? {
        guard healthLedger.ownExport(forDoseID: doseID) != nil || healthLedger.pendingAction(forDoseID: doseID) != nil else { return nil }
        return queueHealthSave(doseID: doseID, now: now, id: id)
    }

    /// Call in the same change that removed a dose. A save that never
    /// started is simply dropped; otherwise only Aurora's own sample is
    /// queued for deletion. Nothing is queued while export is off, so an
    /// earlier copy stays in Health.
    @discardableResult
    public mutating func queueHealthRemoval(doseID: String, now: Millis, id: String) -> HealthPendingAction? {
        guard healthExportActive else { return nil }
        if healthLedger.dropUnstartedSave(forDoseID: doseID), healthLedger.ownExport(forDoseID: doseID) == nil { return nil }
        return enqueueHealthExport(.deleteCaffeine, doseID: doseID, now: now, id: id)
    }

    // MARK: Sleep

    public mutating func addSleep(_ session: SleepSession) {
        sleeps.append(session)
    }

    public mutating func upsertSleepSessions(_ items: [SleepSession], now: Millis) {
        let merged = HealthSleepIdentity.normalize(HealthSleepIdentity.normalize(sleeps) + HealthSleepIdentity.normalize(items))
        sleeps = Self.sortedByEndDescending(Self.withinHealthRetention(merged, now: now))
    }

    /// For providers without sample identity: replaces interval-identified
    /// Health sleep inside the window with `items`, so samples deleted in
    /// Health disappear here too. Manual, sample, and sample-identified
    /// Health sleep is untouched.
    public mutating func replaceHealthSleepWindow(_ items: [SleepSession], windowStart: Millis, windowEnd: Millis, now: Millis) {
        let kept = HealthSleepIdentity.normalize(sleeps).filter {
            !RecordID.isLegacyHealthSleep($0.id) || $0.end < windowStart || $0.start > windowEnd
        }
        let merged = HealthSleepIdentity.normalize(kept + HealthSleepIdentity.normalize(items))
        sleeps = Self.sortedByEndDescending(Self.withinHealthRetention(merged, now: now))
    }

    /// Applies an anchored Health sleep read. Records are keyed by sample
    /// UUID and keep their provenance; deletions remove exactly those UUIDs.
    /// Samples with equal intervals stay separate records; calculations merge
    /// intervals on their own.
    ///
    /// The first anchored read converts pre-identity records conservatively:
    /// a `healthkit:sleep:<start>:<end>` record is replaced only by samples at
    /// exactly that interval, which is what its id was derived from. Any
    /// other one is kept read-only until retention trims it, never matched
    /// to a nearby sample. The anchor is saved with the records.
    @discardableResult
    public mutating func applyHealthSleep(_ changes: HealthSleepChanges, now: Millis) -> HealthSleepImport.Result {
        var result = HealthSleepImport.Result()
        let firstRead = healthLedger.anchor(for: .sleepAnalysis) == nil
        let deleted = Set(changes.deletedSampleUUIDs.map { RecordID.healthSleepID(sampleUUID: $0) })
        let before = sleeps.count
        sleeps.removeAll { deleted.contains($0.id) }
        result.removed = before - sleeps.count
        var incoming: [SleepSession] = []
        for sample in changes.added {
            guard let session = HealthSleepImport.session(from: sample) else {
                result.rejected += 1
                continue
            }
            incoming.removeAll { $0.id == session.id }
            incoming.append(session)
        }
        if firstRead {
            let intervals = Set(incoming.map { HealthSleepIdentity.id(start: $0.start, end: $0.end) })
            let legacy = sleeps.filter { RecordID.isLegacyHealthSleep($0.id) }
            let replaced = legacy.filter { intervals.contains(HealthSleepIdentity.id(start: $0.start, end: $0.end)) }
            result.legacyReplaced = replaced.count
            result.legacyKept = legacy.count - replaced.count
            let replacedIDs = Set(replaced.map(\.id))
            sleeps.removeAll { replacedIDs.contains($0.id) }
        }
        for session in incoming {
            if let index = sleeps.firstIndex(where: { $0.id == session.id }) {
                sleeps[index] = session
            } else {
                sleeps.append(session)
            }
            result.upserted += 1
        }
        sleeps = Self.sortedByEndDescending(Self.withinHealthRetention(sleeps, now: now))
        healthLedger.setAnchor(changes.anchor, for: .sleepAnalysis, at: now)
        return result
    }

    /// Only manual entries can be corrected.
    public mutating func updateManualSleep(id: String, start: Millis? = nil, end: Millis? = nil, note: String?? = nil) {
        guard RecordID.isManualSleep(id), let index = sleeps.firstIndex(where: { $0.id == id }) else { return }
        if let start { sleeps[index].start = start }
        if let end { sleeps[index].end = end }
        if let note { sleeps[index].note = note }
    }

    public mutating func removeManualSleep(id: String) {
        guard RecordID.isManualSleep(id) else { return }
        sleeps.removeAll { $0.id == id }
    }

    // MARK: Energy check-ins

    /// Adds a self-rated check-in, newest first. Invalid entries are refused.
    @discardableResult
    public mutating func addEnergyCheckIn(_ checkIn: EnergyCheckIn, now: Millis) -> DraftValidation {
        let validation = checkIn.validate(now: now)
        guard validation == .valid, !energyCheckIns.contains(where: { $0.id == checkIn.id }) else {
            return validation == .valid ? .invalid("This check-in is already saved.") : validation
        }
        energyCheckIns = Self.stableSorted([checkIn] + energyCheckIns) { $0.recordedAt > $1.recordedAt }
        return .valid
    }

    public mutating func removeEnergyCheckIn(id: String) {
        energyCheckIns.removeAll { $0.id == id }
    }

    // MARK: Reaction Test

    public mutating func addVigilanceSession(_ session: VigilanceSession) {
        vigilanceSessions = Self.stableSorted([session] + vigilanceSessions) { $0.completedAt > $1.completedAt }
    }

    // MARK: Sample Data

    public mutating func loadSampleData(now: Millis, clock: LocalClock) {
        let sample = SampleData.snapshot(now: now, clock: clock)
        doses = Self.stableSorted(doses.filter { !RecordID.isSample($0.id) } + sample.doses) { $0.timestamp > $1.timestamp }
        sleeps = Self.sortedByEndDescending(sleeps.filter { !RecordID.isSample($0.id) } + sample.sleeps)
        vigilanceSessions = Self.stableSorted(vigilanceSessions.filter { !RecordID.isSample($0.id) } + sample.vigilanceSessions) {
            $0.completedAt > $1.completedAt
        }
        demoMode = true
        if !onboarding.completed {
            healthSync = .defaults
            onboarding.completed = true
            onboarding.source = .manual
            onboarding.permissionStatus = .unsupported
            onboarding.completedAt = onboarding.completedAt ?? now
        }
    }

    public mutating func clearSampleData() {
        doses.removeAll { RecordID.isSample($0.id) }
        sleeps.removeAll { RecordID.isSample($0.id) }
        vigilanceSessions.removeAll { RecordID.isSample($0.id) }
        demoMode = false
    }

    /// Deletes every record. Settings, onboarding, appearance and Health
    /// choices stay. The ledger is cleared, so queued Health actions are
    /// dropped and copies already in Health remain there.
    public mutating func deleteAllData() {
        doses = []
        sleeps = []
        vigilanceSessions = []
        energyCheckIns = []
        demoMode = false
        healthSync = .defaults
        healthLedger = .empty
    }

    // MARK: Onboarding and walkthrough

    public mutating func completeOnboarding(now: Millis, source: OnboardingSource? = nil, permissionStatus: HealthPermissionStatus? = nil) {
        if let source { onboarding.source = source }
        if let permissionStatus { onboarding.permissionStatus = permissionStatus }
        onboarding.completed = true
        onboarding.completedAt = now
    }

    public mutating func advanceWalkthrough() {
        onboarding.appWalkthroughStep = Self.clampWalkthroughStep(onboarding.appWalkthroughStep + 1)
    }

    public mutating func completeWalkthrough() {
        onboarding.appWalkthroughCompleted = true
    }

    public var isWalkthroughPending: Bool {
        onboarding.completed && !onboarding.appWalkthroughCompleted
    }
}

extension AppState {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, doses, sleeps, vigilanceSessions, prefs, onboarding, healthSync, demoMode, appearanceMode
        case energyCheckIns, healthLedger, healthChoices
    }

    /// Missing keys fall back to defaults, so a file written by an older
    /// build still opens. `StateMigration` reads the stored version itself,
    /// so a file without one is still migrated as version 1.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? AppState.schemaVersion
        doses = try container.decodeIfPresent([Dose].self, forKey: .doses) ?? []
        sleeps = try container.decodeIfPresent([SleepSession].self, forKey: .sleeps) ?? []
        vigilanceSessions = try container.decodeIfPresent([VigilanceSession].self, forKey: .vigilanceSessions) ?? []
        prefs = try container.decodeIfPresent(Prefs.self, forKey: .prefs) ?? .defaults
        onboarding = try container.decodeIfPresent(Onboarding.self, forKey: .onboarding) ?? .defaults
        healthSync = try container.decodeIfPresent(HealthSync.self, forKey: .healthSync) ?? .defaults
        demoMode = try container.decodeIfPresent(Bool.self, forKey: .demoMode) ?? false
        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        energyCheckIns = try container.decodeIfPresent([EnergyCheckIn].self, forKey: .energyCheckIns) ?? []
        healthLedger = try container.decodeIfPresent(HealthSyncLedger.self, forKey: .healthLedger) ?? .empty
        // Before separate choices, a completed sleep request was the only
        // Health choice, so it carries over as reading sleep.
        healthChoices = try container.decodeIfPresent(HealthChoices.self, forKey: .healthChoices)
            ?? HealthChoices(readSleep: onboarding.permissionStatus == .granted)
    }
}
