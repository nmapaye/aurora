import Foundation

/// One term of the alertness model at an instant. `term` is the model input
/// (0 to 1, or 1 for the baseline) and `points` its signed share of the
/// unclamped score. These are modeled values, never measurements.
public struct EnergyContribution: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case baseline
        /// The generic daily curve, the same for everyone.
        case timeOfDay
        case caffeine
        case sleepDebt
        case inertia
    }

    public var kind: Kind
    public var term: Double
    public var points: Double

    public init(kind: Kind, term: Double, points: Double) {
        self.kind = kind
        self.term = term
        self.points = points
    }
}

/// Inputs the model had no record for at the captured instant.
public enum EnergyMissingInput: String, Codable, Sendable, CaseIterable {
    /// No qualifying sleep block reaches the preceding 18 hours. There is no modeled score.
    case recentSleep
    /// No caffeine in the 24 hours before, but earlier entries still add
    /// modeled active caffeine as they fade.
    case recentCaffeine
    /// No entry adds any active caffeine at this time. The model counts none.
    case caffeine

    public var text: String {
        switch self {
        case .recentSleep: "No recorded sleep block of at least 3 hours reaches the 18 hours before this time, so there is no modeled alertness."
        case .recentCaffeine: "No caffeine is recorded in the 24 hours before this time. Earlier entries still add a modeled amount as they fade."
        case .caffeine: "No caffeine is recorded by this time. The model counts none."
        }
    }
}

public enum EnergyLimitation: String, Codable, Sendable, CaseIterable {
    case notMeasured
    case genericCircadian
    case halfLifeSetting
    /// Things the model has no input for. They limit the estimate and are
    /// never named as a reason for it.
    case unmeasuredFactors

    public var text: String {
        switch self {
        case .notMeasured: "Modeled from your records."
        case .genericCircadian: "Time of day follows a generic daily curve, not your personal rhythm."
        case .halfLifeSetting: "Fades by your half-life setting."
        case .unmeasuredFactors: "Illness, stress, medication, meals, activity, and anything else not recorded here are not part of the model."
        }
    }
}

/// Where an input record came from, read from its id.
public enum EnergyInputSource: String, Codable, Sendable {
    case manual
    case health
    case sample

    public static func of(doseID id: String) -> EnergyInputSource {
        RecordID.isSample(id) ? .sample : (RecordID.isHealthCaffeine(id) ? .health : .manual)
    }

    public static func of(sleepID id: String) -> EnergyInputSource {
        RecordID.isSample(id) ? .sample : (RecordID.isHealthSleep(id) ? .health : .manual)
    }
}

/// The records an estimate was computed from, copied at capture so the
/// snapshot still explains itself after records change. Only plain values
/// are kept: ids, times, amounts and Health provenance identifiers.
public struct EnergyEvidence: Codable, Equatable, Sendable {
    /// Entries with at least this much modeled active caffeine are listed one
    /// by one; fainter ones are summed in `fadedCaffeine`. Evidence only; the
    /// model itself uses every entry.
    public static let itemizedMinimumMg: Double = 0.01

    public struct CaffeineInput: Codable, Equatable, Sendable {
        public var recordID: String
        public var source: EnergyInputSource
        public var timestamp: Millis
        public var mg: Double
        /// This entry's modeled active caffeine at capture.
        public var activeMg: Double
        public var healthSampleUUID: String?
        public var healthSourceBundleIdentifier: String?
    }

    /// Entries still adding some active caffeine, each below
    /// `itemizedMinimumMg`.
    public struct FadedCaffeine: Codable, Equatable, Sendable {
        public var count: Int
        public var activeMg: Double
        public var latestTimestamp: Millis
        public var includesSample: Bool
    }

    public struct SleepInput: Codable, Equatable, Sendable {
        public var recordID: String
        public var source: EnergyInputSource
        public var start: Millis
        public var end: Millis
        /// Hours of this record inside the 24 hours before capture, before
        /// overlapping records are merged.
        public var hoursInWindow: Double
        /// Part of the latest sleep episode, which sets the wake-up term.
        public var inLatestEpisode: Bool
    }

    /// The start of the 24 hours before capture.
    public var windowStart: Millis
    /// Total modeled active caffeine, equal to `Caffeine.activeMg`.
    public var activeCaffeineMg: Double
    /// Every entry adding at least `itemizedMinimumMg`, oldest first.
    public var caffeine: [CaffeineInput]
    public var fadedCaffeine: FadedCaffeine?
    /// Sleep inside the 24 hours before capture or in the latest episode,
    /// earliest first.
    public var sleep: [SleepInput]
    /// End of the latest sleep episode, when the wake-up term applies.
    public var lastWakeAt: Millis?

    public var includesSample: Bool {
        caffeine.contains { $0.source == .sample }
            || fadedCaffeine?.includesSample == true
            || sleep.contains { $0.source == .sample }
    }

    /// Any contributing entry dated inside the 24 hours before capture.
    public var hasRecentCaffeine: Bool {
        caffeine.contains { $0.timestamp > windowStart } || (fadedCaffeine?.latestTimestamp ?? -.infinity) > windowStart
    }

    /// Any entry adds active caffeine at capture.
    public var hasActiveCaffeine: Bool { !caffeine.isEmpty || fadedCaffeine != nil }

    static func capture(at t: Millis, doses: [Dose], sleeps: [SleepSession], halfLifeHours: Double) -> EnergyEvidence {
        let windowStart = t - dayMs
        let halfLifeMs = halfLifeHours * hourMs
        var caffeine: [CaffeineInput] = []
        var faded: FadedCaffeine?
        let ordered = doses.filter { $0.timestamp <= t }.sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
        for dose in ordered {
            // The same term `Caffeine.activeMg` adds for this entry.
            let active = dose.mg * pow(0.5, (t - dose.timestamp) / halfLifeMs)
            guard active > 0 else { continue }
            let isSample = RecordID.isSample(dose.id)
            if active >= itemizedMinimumMg {
                caffeine.append(CaffeineInput(
                    recordID: dose.id, source: .of(doseID: dose.id), timestamp: dose.timestamp, mg: dose.mg, activeMg: active,
                    healthSampleUUID: dose.health?.sampleUUID, healthSourceBundleIdentifier: dose.health?.sourceBundleIdentifier
                ))
            } else if var current = faded {
                current.count += 1
                current.activeMg += active
                current.latestTimestamp = dose.timestamp
                current.includesSample = current.includesSample || isSample
                faded = current
            } else {
                faded = FadedCaffeine(count: 1, activeMg: active, latestTimestamp: dose.timestamp, includesSample: isSample)
            }
        }

        // Mirrors `SleepInertia`: the latest episode that started and ended
        // by capture, with brief awakenings joined.
        let episode = SleepIntervals.merge(sleeps.filter { $0.start <= t }, gapMs: SleepIntervals.briefAwakeningMs)
            .filter { $0.end <= t }
            .max { $0.end < $1.end }
        let wakeApplies = SleepInertia.value(at: t, sleeps: sleeps) > 0
        let sleep = sleeps
            .compactMap { session -> SleepInput? in
                let hours = max(0, min(session.end, t) - max(session.start, windowStart)) / hourMs
                let inEpisode = wakeApplies && episode.map { session.start >= $0.start && session.end <= $0.end && session.end > session.start } == true
                guard (session.end > windowStart && session.start <= t) || inEpisode else { return nil }
                return SleepInput(
                    recordID: session.id, source: .of(sleepID: session.id), start: session.start, end: session.end,
                    hoursInWindow: hours, inLatestEpisode: inEpisode
                )
            }
            .sorted { ($0.start, $0.recordID) < ($1.start, $1.recordID) }

        return EnergyEvidence(
            windowStart: windowStart,
            activeCaffeineMg: Caffeine.activeMg(at: t, doses: doses, halfLifeHours: halfLifeHours),
            caffeine: caffeine,
            fadedCaffeine: faded,
            sleep: sleep,
            lastWakeAt: wakeApplies ? episode?.end : nil
        )
    }
}

/// A versioned snapshot of modeled alertness at one instant, with everything
/// needed to explain it later without recomputing from changed records.
/// The score is the existing alertness estimate, rounded the same way, and is
/// present only when a recorded sleep block of at least three hours reaches
/// the preceding 18 hours. Ongoing sleep is clipped to the captured instant.
public struct EnergyEstimate: Codable, Equatable, Sendable {
    /// 2 added `evidence`, the `caffeine` missing input and the
    /// `unmeasuredFactors` limitation.
    public static let currentVersion = 2
    /// Scalar terms are unchanged, but new snapshots also apply the
    /// three-hour/eighteen-hour sleep eligibility rule. Keep this distinct
    /// from historical `alertness-1` snapshots; their captured values stay put.
    public static let currentModelVersion = "alertness-1-main-sleep-3h-18h"
    public static let title = "Modeled alertness"

    public var version: Int
    public var modelVersion: String
    public var capturedAt: Millis
    public var timeZoneIdentifier: String
    public var halfLifeHours: Double
    public var targetSleepHours: Double
    public var sleepHoursLast24: Double
    /// Rounded 0 to 100 model output. Not a percentage.
    public var modeledScore: Int?
    /// Empty when there is no score, so missing sleep never reads as data.
    public var contributions: [EnergyContribution]
    public var missingInputs: [EnergyMissingInput]
    /// Any contributing record is Sample Data, including older caffeine
    /// that still adds active caffeine.
    public var includesSample: Bool
    public var limitations: [EnergyLimitation]
    public var evidence: EnergyEvidence

    public static func capture(
        at t: Millis,
        doses: [Dose],
        sleeps: [SleepSession],
        inputs: EstimateInputs
    ) -> EnergyEstimate {
        let estimate = Summary.estimateAlertness(at: t, doses: doses, sleeps: sleeps, inputs: inputs)
        let sleepHours = SleepDebt.totalHoursLast24(at: t, sleeps: sleeps)
        let evidence = EnergyEvidence.capture(at: t, doses: doses, sleeps: sleeps, halfLifeHours: inputs.halfLifeHours)

        var missing: [EnergyMissingInput] = []
        if estimate.score == nil { missing.append(.recentSleep) }
        if !evidence.hasActiveCaffeine {
            missing.append(.caffeine)
        } else if !evidence.hasRecentCaffeine {
            missing.append(.recentCaffeine)
        }

        var contributions: [EnergyContribution] = []
        if estimate.score != nil {
            let circadian = Circadian.value(at: t, clock: inputs.clock)
            let effect = Caffeine.activeEffect(at: t, doses: doses, halfLifeHours: inputs.halfLifeHours)
            let debt = SleepDebt.value(at: t, sleeps: sleeps, targetHours: inputs.targetSleepHours)
            let inertia = SleepInertia.value(at: t, sleeps: sleeps)
            contributions = [
                EnergyContribution(kind: .baseline, term: 1, points: Alertness.baseline),
                EnergyContribution(kind: .timeOfDay, term: circadian, points: Alertness.circadianWeight * circadian),
                EnergyContribution(kind: .caffeine, term: effect, points: Alertness.caffeineWeight * effect),
                EnergyContribution(kind: .sleepDebt, term: debt, points: -(Alertness.sleepDebtWeight * debt)),
                EnergyContribution(kind: .inertia, term: inertia, points: -(Alertness.inertiaWeight * inertia)),
            ]
        }

        return EnergyEstimate(
            version: currentVersion,
            modelVersion: currentModelVersion,
            capturedAt: t,
            timeZoneIdentifier: inputs.clock.timeZone.identifier,
            halfLifeHours: inputs.halfLifeHours,
            targetSleepHours: inputs.targetSleepHours,
            sleepHoursLast24: sleepHours,
            modeledScore: estimate.score,
            contributions: contributions,
            missingInputs: missing,
            includesSample: evidence.includesSample,
            limitations: EnergyLimitation.allCases,
            evidence: evidence
        )
    }

    /// The contributions summed in model order, then clamped: equal to
    /// `Alertness.score` whenever there is a score.
    public var unroundedScore: Double? {
        guard modeledScore != nil else { return nil }
        return min(100, max(0, contributions.reduce(0) { $0 + $1.points }))
    }

    public var summary: String {
        guard let modeledScore else { return "\(Self.title) unavailable. No recorded sleep block of at least 3 hours reaches the 18 hours before this time." }
        return "\(Self.title) \(modeledScore) of 100, modeled from sleep, caffeine and time of day."
            + (includesSample ? " Includes Sample Data." : "")
    }

    /// The scale beside a score. The title already says it's modeled.
    public static let scaleLabel = "Scale 0–100"

    /// What's missing when there is no score, in the model's own terms: a
    /// sleep block of at least 3 hours reaching the 18 hours before
    /// (`currentModelVersion`). A nap or an older night doesn't count.
    public static let missingSleepLine = "No sleep of 3 hours or more in the last 18 hours."
}
