import Foundation

/// Everything Aurora stores. The app keeps one value of this and saves it
/// whole; every change goes through the mutating functions below, which
/// match the React Native store's actions.
public struct AppState: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
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

    /// This state without records whose times have no calendar date
    /// (`isValidRecordTime`), as the legacy import already drops them. Only a
    /// hand-edited or damaged `state.json` holds such records; the app never
    /// writes one.
    public func droppingInvalidTimes() -> AppState {
        var state = self
        state.doses = doses.filter { isValidRecordTime($0.timestamp) }
        state.sleeps = sleeps.filter { isValidRecordTime($0.start) && isValidRecordTime($0.end) }
        state.vigilanceSessions = vigilanceSessions.filter { isValidRecordTime($0.startedAt) && isValidRecordTime($0.completedAt) }
        if let completedAt = onboarding.completedAt, !isValidRecordTime(completedAt) { state.onboarding.completedAt = nil }
        if let lastSyncedAt = healthSync.lastSyncedAt, !isValidRecordTime(lastSyncedAt) { state.healthSync.lastSyncedAt = nil }
        return state
    }

    // MARK: Caffeine

    public mutating func addDose(_ dose: Dose) {
        doses.append(dose)
    }

    /// Replaces an entry's recorded fields. The entry keeps its id. Sample
    /// Data is read-only, so sample entries are left alone.
    public mutating func updateDose(id: String, timestamp: Millis, mg: Double, source: String?, note: String?) {
        guard !RecordID.isSample(id), let index = doses.firstIndex(where: { $0.id == id }) else { return }
        doses[index].timestamp = timestamp
        doses[index].mg = mg
        doses[index].source = source
        doses[index].note = note
    }

    public mutating func updateDose(id: String, with patch: Dose) {
        updateDose(id: id, timestamp: patch.timestamp, mg: patch.mg, source: patch.source, note: patch.note)
    }

    /// Sample entries are removed only by clearing Sample Data.
    public mutating func removeDose(id: String) {
        guard !RecordID.isSample(id) else { return }
        doses.removeAll { $0.id == id }
    }

    // MARK: Sleep

    public mutating func addSleep(_ session: SleepSession) {
        sleeps.append(session)
    }

    public mutating func upsertSleepSessions(_ items: [SleepSession], now: Millis) {
        let merged = HealthSleepIdentity.normalize(HealthSleepIdentity.normalize(sleeps) + HealthSleepIdentity.normalize(items))
        sleeps = Self.sortedByEndDescending(Self.withinHealthRetention(merged, now: now))
    }

    /// Replaces Health-imported sleep inside the window with `items`, so
    /// samples deleted in Health disappear here too. Manual and sample sleep
    /// is untouched.
    public mutating func replaceHealthSleepWindow(_ items: [SleepSession], windowStart: Millis, windowEnd: Millis, now: Millis) {
        let kept = HealthSleepIdentity.normalize(sleeps).filter {
            !RecordID.isHealthSleep($0.id) || $0.end < windowStart || $0.start > windowEnd
        }
        let merged = HealthSleepIdentity.normalize(kept + HealthSleepIdentity.normalize(items))
        sleeps = Self.sortedByEndDescending(Self.withinHealthRetention(merged, now: now))
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

    /// Deletes every record. Settings, onboarding and appearance stay.
    public mutating func deleteAllData() {
        doses = []
        sleeps = []
        vigilanceSessions = []
        demoMode = false
        healthSync = .defaults
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
    }

    /// Missing keys fall back to defaults, so a file written by an older
    /// build still opens.
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
    }
}
