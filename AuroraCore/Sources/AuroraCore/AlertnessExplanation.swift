import Foundation

/// "Why this number": the current modeled alertness explained from the
/// inputs the estimator actually used. Pure and deterministic. Every figure
/// shown is read from an `EnergyEstimate` (`EnergyEstimate.capture`, which
/// runs `Summary.estimateAlertness` and the `Alertness` terms in
/// Algorithms.swift); nothing is recomputed or guessed here.
///
/// A missing record is never shown as 0: with no sleep recorded the sleep
/// line says so and carries no points, and with no active caffeine the
/// caffeine line says so and carries no points.
///
/// Notes stay to the facts needed to read the points (the starting value
/// and where the scale stops). Reassurance lines ("an estimate, not a
/// measurement", rounding) are not repeated here: the card already carries
/// the "Modeled" label and Terms hold the disclaimer (owner rule, #87).
public struct AlertnessExplanation: Equatable, Sendable {
    public struct Factor: Equatable, Identifiable, Sendable {
        public enum Kind: String, Sendable {
            case start, sleep, caffeine, timeOfDay, wakeUp
        }

        public var kind: Kind
        public var title: String
        /// Signed model points as shown ("+12", "−8", "0"). Nil when there
        /// is no score or no record for this input.
        public var points: String?
        public var detail: String
        public var id: String { kind.rawValue }
    }

    public static let title = "Why This Number"

    /// The rounded score, or nil when the model has none.
    public var score: Int?
    public var headline: String
    public var factors: [Factor]
    /// The input with the largest share of the score, by size of its points.
    public var largest: Factor.Kind?
    public var notes: [String]
    public var includesSample: Bool

    public static func explain(_ estimate: EnergyEstimate, text: DateText) -> AlertnessExplanation {
        let part = { (kind: EnergyContribution.Kind) in estimate.contributions.first { $0.kind == kind } }
        let scored = estimate.modeledScore != nil
        let evidence = estimate.evidence
        let hasSleep = estimate.sleepHoursLast24 > 0
        let hasCaffeine = evidence.hasActiveCaffeine

        var factors: [Factor] = []

        // Where every estimate starts, so the points read as a sum.
        if scored, let baseline = part(.baseline) {
            factors.append(Factor(kind: .start, title: "Starting point", points: baseline.pointsText,
                                  detail: "Every estimate starts here; each part below adds or takes away points."))
        }

        // Sleep.
        let sleepDetail: String
        if !hasSleep {
            sleepDetail = "No sleep recorded in the last 24 hours."
        } else if scored {
            sleepDetail = "Recorded sleep in the last 24 hours: \(formatSleepHours(estimate.sleepHoursLast24)). Your goal: \(numberText(estimate.targetSleepHours))h."
        } else {
            sleepDetail = "Recorded sleep in the last 24 hours: \(formatSleepHours(estimate.sleepHoursLast24)), but none is a block of 3 hours or more in the last 18 hours."
        }
        factors.append(Factor(kind: .sleep, title: "Sleep", points: hasSleep ? part(.sleepDebt)?.pointsText : nil, detail: sleepDetail))

        // Shortly after waking, only when the model applied it.
        if let inertia = part(.inertia), inertia.term > 0, let wake = evidence.lastWakeAt {
            factors.append(Factor(kind: .wakeUp, title: "Just woke up", points: inertia.pointsText,
                                  detail: "Recorded sleep ended at \(text.clockTime(wake)). The model lowers the estimate for a while after waking."))
        }

        // Caffeine.
        let caffeineDetail = hasCaffeine
            ? "\(numberText(jsRound(evidence.activeCaffeineMg))) mg modeled as active now, fading by your \(numberText(estimate.halfLifeHours))h half-life setting."
            : "No caffeine recorded by this time."
        factors.append(Factor(kind: .caffeine, title: "Active caffeine", points: hasCaffeine ? part(.caffeine)?.pointsText : nil, detail: caffeineDetail))

        // Time of day.
        factors.append(Factor(kind: .timeOfDay, title: "Time of day", points: part(.timeOfDay)?.pointsText,
                              detail: "At \(text.clockTime(estimate.capturedAt)), on the same daily curve for everyone, by local time."))

        // The largest part by size, among inputs that have points.
        let sized: [(Factor.Kind, Double)] = [
            (.sleep, hasSleep ? part(.sleepDebt)?.points : nil),
            (.wakeUp, factors.contains { $0.kind == .wakeUp } ? part(.inertia)?.points : nil),
            (.caffeine, hasCaffeine ? part(.caffeine)?.points : nil),
            (.timeOfDay, part(.timeOfDay)?.points),
        ].compactMap { kind, points in points.map { (kind, abs($0)) } }
        let largest = sized.filter { jsRoundInt($0.1) != 0 }.max { $0.1 < $1.1 }?.0

        var notes: [String] = []
        if scored {
            let sum = estimate.contributions.reduce(0) { $0 + $1.points }
            if sum > 100 { notes.append("The parts add up to more than 100, and the scale stops at 100.") }
            if sum < 0 { notes.append("The parts add up to less than 0, and the scale stops at 0.") }
        }

        let headline = estimate.modeledScore.map { "\(EnergyEstimate.title) \($0) of 100, from your recorded sleep, active caffeine and the time of day." }
            ?? "No \(EnergyEstimate.title.lowercased()) right now. \(EnergyEstimate.missingSleepLine)"

        return AlertnessExplanation(
            score: estimate.modeledScore,
            headline: headline,
            factors: factors,
            largest: scored ? largest : nil,
            notes: notes,
            includesSample: estimate.includesSample
        )
    }

    /// Every line, for copy checks and VoiceOver.
    public var allText: [String] {
        [headline] + factors.flatMap { [$0.title, $0.points ?? "", $0.detail] } + notes
    }
}
