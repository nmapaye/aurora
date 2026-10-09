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
    /// No sleep in the 24 hours before. There is no modeled score.
    case recentSleep
    /// No caffeine in the 24 hours before. The model counts none.
    case recentCaffeine

    public var text: String {
        switch self {
        case .recentSleep: "No sleep is recorded in the 24 hours before this time, so there is no modeled alertness."
        case .recentCaffeine: "No caffeine is recorded in the 24 hours before this time. The model counts none."
        }
    }
}

public enum EnergyLimitation: String, Codable, Sendable, CaseIterable {
    case notMeasured
    case genericCircadian
    case halfLifeSetting

    public var text: String {
        switch self {
        case .notMeasured: "Modeled from your records. It is not a measurement of how you feel or perform."
        case .genericCircadian: "Time of day follows a generic daily curve, not your personal rhythm."
        case .halfLifeSetting: "Caffeine fades by the half-life in Settings, not a measured rate."
        }
    }
}

/// A versioned snapshot of modeled alertness at one instant, with everything
/// needed to explain it later without recomputing from changed records.
/// The score is the existing alertness estimate, rounded the same way, and is
/// present only when sleep is recorded in the 24 hours before.
public struct EnergyEstimate: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// The React Native port's model, unchanged.
    public static let currentModelVersion = "alertness-1"
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
    public var includesSample: Bool
    public var limitations: [EnergyLimitation]

    public static func capture(
        at t: Millis,
        doses: [Dose],
        sleeps: [SleepSession],
        inputs: EstimateInputs
    ) -> EnergyEstimate {
        let estimate = Summary.estimateAlertness(at: t, doses: doses, sleeps: sleeps, inputs: inputs)
        let windowStart = t - dayMs
        let sleepHours = SleepDebt.totalHoursLast24(at: t, sleeps: sleeps)
        let recentDoses = doses.filter { $0.timestamp > windowStart && $0.timestamp <= t }
        let includesSample =
            sleeps.contains { $0.end > windowStart && $0.start <= t && RecordID.isSample($0.id) } ||
            recentDoses.contains { RecordID.isSample($0.id) }

        var missing: [EnergyMissingInput] = []
        if estimate.score == nil { missing.append(.recentSleep) }
        if recentDoses.isEmpty { missing.append(.recentCaffeine) }

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
            includesSample: includesSample,
            limitations: EnergyLimitation.allCases
        )
    }

    /// The contributions summed in model order, then clamped: equal to
    /// `Alertness.score` whenever there is a score.
    public var unroundedScore: Double? {
        guard modeledScore != nil else { return nil }
        return min(100, max(0, contributions.reduce(0) { $0 + $1.points }))
    }

    public var summary: String {
        guard let modeledScore else { return "\(Self.title) unavailable. No sleep is recorded in the 24 hours before this time." }
        return "\(Self.title) \(modeledScore) on a 0 to 100 model scale. Estimated from recorded sleep, caffeine, and a generic time-of-day curve; not measured."
            + (includesSample ? " Includes Sample Data." : "")
    }
}
