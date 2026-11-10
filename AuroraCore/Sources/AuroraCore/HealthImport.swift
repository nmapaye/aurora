import Foundation

/// Health sleep samples arrive as start/end pairs. Only the asleep values are
/// kept; in-bed and awake samples are not sleep.
public struct HealthSleepSample: Equatable, Sendable {
    public var start: Millis
    public var end: Millis
    /// Present when the provider reads sample identity (anchored reads).
    public var provenance: HealthSampleProvenance?

    public init(start: Millis, end: Millis, provenance: HealthSampleProvenance? = nil) {
        self.start = start
        self.end = end
        self.provenance = provenance
    }
}

/// An anchored read of asleep samples: added samples with their identity,
/// and the UUIDs of samples deleted, since the previous anchor.
public struct HealthSleepChanges: Equatable, Sendable {
    public var added: [HealthSleepSample]
    public var deletedSampleUUIDs: [String]
    /// The archived `HKQueryAnchor` to resume from.
    public var anchor: Data
    /// This was one bounded page and more changes follow `anchor`.
    public var hasMore: Bool

    public init(added: [HealthSleepSample], deletedSampleUUIDs: [String], anchor: Data, hasMore: Bool = false) {
        self.added = added
        self.deletedSampleUUIDs = deletedSampleUUIDs
        self.anchor = anchor
        self.hasMore = hasMore
    }
}

public enum HealthSleepImport {
    public struct Result: Equatable, Sendable {
        public var upserted = 0
        public var removed = 0
        public var rejected = 0
        /// Pre-identity `healthkit:sleep:<start>:<end>` records replaced by
        /// the sample records for exactly that interval.
        public var legacyReplaced = 0
        /// Pre-identity records still without a sample at exactly their
        /// interval, kept read-only until retention trims them.
        public var legacyKept = 0
        public var pages = 0
        public var hasMore = false

        public init() {}

        mutating func add(_ page: Result) {
            upserted += page.upserted
            removed += page.removed
            rejected += page.rejected
            legacyReplaced += page.legacyReplaced
            legacyKept = page.legacyKept
        }
    }

    /// Identity, a finite interval, and an end after the start.
    public static func isValid(_ sample: HealthSleepSample) -> Bool {
        guard let provenance = sample.provenance, !provenance.sampleUUID.isEmpty else { return false }
        return sample.start.isFinite && sample.end.isFinite && sample.start < sample.end
    }

    /// Anchored sleep reads ask Health only for asleep samples that overlap
    /// the last `HealthImport.refreshDays`. Reading from the beginning of
    /// Health history, oldest first in bounded pages, could take many
    /// refreshes to reach last night.
    public static func anchoredReadStart(now: Millis) -> Millis {
        now - HealthImport.refreshDays * dayMs
    }

    public static func session(from sample: HealthSleepSample) -> SleepSession? {
        guard isValid(sample), let provenance = sample.provenance else { return nil }
        return SleepSession(id: RecordID.healthSleepID(sampleUUID: provenance.sampleUUID), start: sample.start, end: sample.end, type: .sleep, health: provenance)
    }
}

/// What an anchored Health sleep read asks for: asleep stages only, and only
/// samples that overlap the last `HealthImport.refreshDays`. HealthKitService
/// builds its HealthKit predicate from this and applies `matches` to what
/// comes back, so the rule lives in one tested place.
public struct HealthSleepReadFilter: Equatable, Sendable {
    /// Nil reads all of Health history (how the anchored read behaved before
    /// it had a date predicate).
    public let windowStart: Millis?
    public let asleepValues: Set<Int>

    public init(windowStart: Millis?, asleepValues: Set<Int> = HealthImport.asleepValues) {
        self.windowStart = windowStart
        self.asleepValues = asleepValues
    }

    public static func anchored(now: Millis) -> HealthSleepReadFilter {
        HealthSleepReadFilter(windowStart: HealthSleepImport.anchoredReadStart(now: now))
    }

    /// HealthKit's sample predicate with a start, no end and no options
    /// matches any sample whose span reaches past the start, so a night that
    /// began before the window comes back whole; one ending exactly at the
    /// start doesn't overlap it.
    public func matches(start: Millis, end: Millis, value: Int) -> Bool {
        guard start.isFinite, end.isFinite, asleepValues.contains(value) else { return false }
        guard let windowStart else { return true }
        return end > windowStart
    }
}

public enum HealthImport {
    public static let refreshDays: Double = 30
    public static let onboardingImportDays: Double = 14
    /// Foreground refreshes run at most this often.
    public static let refreshIntervalMs: Millis = 15 * minuteMs

    public static let noSleepMessage =
        "No recent sleep found in Health. Check that Aurora can read Sleep in the Health app, or add sleep manually."
    public static let importingMessage = "Importing recent sleep from Health."

    /// HealthKit `HKCategoryValueSleepAnalysis` raw values that mean asleep:
    /// asleep (unspecified) 1, core 3, deep 4, REM 5.
    public static let asleepValues: Set<Int> = [1, 3, 4, 5]
    /// Most samples (added plus deleted) one anchored read returns; the
    /// filter's limit counts only matching samples.
    public static let anchoredPageSize = 500

    /// Nights rather than samples: one Watch night can be dozens of stage
    /// segments.
    public static func countNights(_ samples: [HealthSleepSample]) -> Int {
        SleepIntervals.merge(samples.map { Interval(start: $0.start, end: $0.end) }, gapMs: SleepIntervals.briefAwakeningMs).count
    }

    public static func describeImportedNights(_ nights: Int) -> String {
        nights > 0 ? "Imported \(nights) \(nights == 1 ? "night" : "nights") of sleep from Health." : noSleepMessage
    }

    public static func sessions(from samples: [HealthSleepSample]) -> [SleepSession] {
        samples.map { SleepSession(id: HealthSleepIdentity.id(start: $0.start, end: $0.end), start: $0.start, end: $0.end, type: .sleep) }
    }

    /// Applies an import of the last `days` to `state`, replacing Aurora's
    /// copy of that window so edits and deletions made in Health carry over.
    public static func apply(
        _ samples: [HealthSleepSample],
        days: Double,
        now: Millis,
        to state: inout AppState
    ) -> Int {
        let windowStart = now - days * dayMs
        state.replaceHealthSleepWindow(sessions(from: samples), windowStart: windowStart, windowEnd: now, now: now)
        let nights = countNights(samples)
        state.healthSync.importedCount = nights
        state.healthSync.importStatus = .succeeded
        state.healthSync.lastSyncedAt = now
        state.healthSync.lastMessage = describeImportedNights(nights)
        return nights
    }

    /// Status after an anchored sleep read: nights of Health sleep recorded in
    /// the refresh window, merged as calculations merge them.
    public static func recordAnchoredRead(now: Millis, hasMore: Bool = false, to state: inout AppState) {
        let windowStart = now - refreshDays * dayMs
        let recent = state.sleeps.filter { RecordID.isHealthSleep($0.id) && $0.end >= windowStart && $0.start <= now }
        let nights = countNights(recent.map { HealthSleepSample(start: $0.start, end: $0.end) })
        state.healthSync.importedCount = nights
        state.healthSync.importStatus = hasMore ? .partial : .succeeded
        state.healthSync.lastSyncedAt = now
        state.healthSync.lastMessage = hasMore ? partialMessage : describeImportedNights(nights)
    }

    public static let partialMessage =
        "Imported part of your Health sleep so far. Aurora reads a limited amount at a time and continues at the next refresh."

    public static func recordFailure(_ message: String, prefix: String = "Health refresh failed.", now: Millis, to state: inout AppState) {
        state.healthSync.importStatus = .failed
        state.healthSync.lastSyncedAt = now
        state.healthSync.lastMessage = "\(prefix) \(message)"
    }

    /// Whether a quiet foreground Health refresh is due.
    public static func shouldRefresh(state: AppState, now: Millis) -> Bool {
        guard state.onboarding.completed, !state.demoMode,
              state.healthChoices.readSleep,
              state.healthSync.importStatus != .importing else { return false }
        // A partial read continues at the next permitted opportunity.
        if state.healthSync.importStatus == .partial { return true }
        guard let last = state.healthSync.lastSyncedAt else { return true }
        return now - last >= refreshIntervalMs
    }
}
